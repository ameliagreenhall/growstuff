namespace :growstuff do

  desc "Add an admin user, by name"
  # usage: rake growstuff:admin_user name=skud

  task :admin_user => :environment do

    member = Member.find_by_login_name(ENV['name']) or raise "Usage: rake growstuff:admin_user name=whoever (login name is case-sensitive)"
    admin  = Role.find_or_create_by_name!('admin')
    member.roles << admin
  end

  desc "Upload crops from a CSV file"
  # usage: rake growstuff:import_crops file=filename.csv

  task :import_crops => :environment do
    require 'csv'

    @file = ENV['file'] or raise "Usage: rake growstuff:import_crops file=file.csv"

    puts "Loading crops from #{@file}..."
    CSV.foreach(@file) do |row|
      Crop.create_from_csv(row)
    end
    puts "Finished loading crops"

  end

  desc "Depopulate Null Island"
  # this fixes up anyone who has erroneously wound up with a 0,0 lat/long
  task :depopulate_null_island => :environment do
    Member.find_each do |m|
      if m.location and (m.latitude == nil and m.longitude == nil)
        m.geocode
        m.save
      end
    end
  end

  desc "One-off tasks needed at various times and kept for posterity"
  namespace :oneoff do

    desc "May 2013: replace any empty notification subjects with (no subject)"
    task :empty_subjects => :environment do

      # this is inefficient as it checks every Notification, but the
      # site is small and there aren't many of them, so it shouldn't matter
      # for this one-off script.
      Notification.all.each do |n|
        n.replace_blank_subject
        n.save
      end
    end

    desc "May 2013: replace any empty garden names with Garden"
    task :empty_garden_names => :environment do

      # this is inefficient as it checks every Garden, but the
      # site is small and there aren't many of them, so it shouldn't matter
      # for this one-off script.
      Garden.all.each do |g|
        if g.name.nil? or g.name =~ /^\s*$/
          g.name = "Garden"
          g.save
        end
      end
    end


    desc "June 2013: create account types and products."
    task :setup_shop => :environment do
      puts "Adding account types..."
      AccountType.find_or_create_by_name(
        :name => "Free",
        :is_paid => false,
        :is_permanent_paid => false
      )
      @paid_account = AccountType.find_or_create_by_name(
        :name => "Paid",
        :is_paid => true,
        :is_permanent_paid => false
      )
      @seed_account = AccountType.find_or_create_by_name(
        :name => "Seed",
        :is_paid => true,
        :is_permanent_paid => true
      )
      @staff_account = AccountType.find_or_create_by_name(
        :name => "Staff",
        :is_paid => true,
        :is_permanent_paid => true
      )

      puts "Adding products..."
      Product.find_or_create_by_name(
        :name => "Annual subscription",
        :description => "An annual subscription gives you access to paid account features for one year.  Does not auto-renew.",
        :min_price => 3000,
        :account_type_id => @paid_account.id,
        :paid_months => 12
      )
      Product.find_or_create_by_name(
        :name => "Seed account",
        :description => "A seed account helps Growstuff grow in its early days.  It gives you all the features of a paid account, in perpetuity.  This account type never expires.",
        :min_price => 15000,
        :account_type_id => @seed_account.id,
      )

      puts "Giving each member an account record..."
      Member.all.each do |m|
        unless m.account
          Account.create(:member_id => m.id)
        end
      end

      puts "Making Skud a staff account..."
      @skud = Member.find_by_login_name('Skud')
      if @skud
        @skud.account.account_type = @staff_account
        @skud.account.save
      end

      puts "Done setting up shop."
    end

    desc "June 2013: replace nil account_types with free accounts"
    task :nil_account_type => :environment do

      free = AccountType.find_by_name("Free")
      raise "Free account type not found: run rake growstuff:oneoff:setup_shop"\
        unless free
      Account.all.each do |a|
        unless a.account_type
          a.account_type = free
          a.save
        end
      end
    end

    desc "July 2013: replace nil seed.tradable_to with nowhere"
    task :tradable_to_nowhere => :environment do

      Seed.all.each do |s|
        unless s.tradable_to
          s.tradable_to = 'nowhere'
          s.save
        end
      end
    end

    desc "August 2013: set up plantings_count cache on crop"
    task :reset_crop_plantings_count => :environment do

      Crop.find_each do |c|
        Crop.reset_counters c.id, :plantings
      end
    end

    desc "August 2013: set default creator on existing crops"
    task :set_default_crop_creator => :environment do

      cropbot = Member.find_by_login_name("cropbot")
      raise "cropbot not found: create cropbot member on site or run rake db:seed" unless cropbot
      cropbot.account.account_type = AccountType.find_by_name("Staff") # set this just because it's nice
      cropbot.account.save
      Crop.find_each do |crop|
        unless crop.creator
          crop.creator = cropbot
          crop.save
        end
      end
      ScientificName.find_each do |sn|
        unless sn.creator
          sn.creator = cropbot
          sn.save
        end
      end

    end

    desc "August 2013: set planting owner"
    task :set_planting_owner => :environment do
      Planting.find_each do |p|
        p.owner = p.garden.owner
        p.save
      end
    end

    desc "August 2013: initialize member planting counter"
    task :initialize_member_planting_count => :environment do
      Member.find_each do |m|
        Member.reset_counters m.id, :plantings
      end
    end

    desc "October 2013: set garden locations to member locations"
    task :initialize_garden_locations => :environment do
      Member.located.find_each do |m|
        m.gardens.each do |g|
          if g.location.blank?
            g.location = m.location
            g.latitude = m.latitude
            g.longitude = m.longitude
            g.save
          end
        end
      end
    end

    desc "October 2013: import initial plant parts"
    task :import_plant_parts => :environment do
      plant_parts = [
        'fruit',
        'flower',
        'seed',
        'pod',
        'leaf',
        'stem',
        'bark',
        'bulb',
        'root',
        'tuber',
        'whole plant',
        'other'
      ]
      plant_parts.each do |pp|
        PlantPart.find_or_create_by_name!(pp)
      end
    end
  end

end
