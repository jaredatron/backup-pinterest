#!/usr/bin/env ruby
# encoding: utf-8

require 'capybara'
require 'capybara/dsl'
require 'pry'
require 'pathname'
require 'colorize'

Capybara.register_driver :selenium do |app|
  Capybara::Selenium::Driver.new(app, :browser => :chrome)
end

Capybara.default_driver         = :selenium
Capybara.ignore_hidden_elements = true
Capybara.default_selector       = :css

class BackupPinterest
  include Capybara::DSL

  PINTEREST = URI.parse('https://pinterest.com/')

  def initialize
    @username = ARGV.shift or usage!
    @email    = ARGV.shift or usage!
    @password = ARGV.shift or usage!
    @root     = Pathname ARGV.shift || File.expand_path('..', __FILE__)
  end
 
  def usage!
    warn "backup username email password [destination]"
    exit!
  end
 
  def backup!
    # binding.pry
    login!
    get_list_of_boards!
    get_images!
  end

  private

  def login!
    puts "Logging in as #{@username} (#{@email})"
    visit PINTEREST + '/login'
    fill_in 'username_or_email', with: @email
    fill_in 'password', with: @password
    page.find("[type=submit]").click
  end

  def get_list_of_boards!
    visit PINTEREST + @username
    # need to wait for boards loaded
    sleep 5

    puts "getting list of boards…"
    
    boards = js <<-JS
      $('.UserBoards .Board > a').map(function(){
        return [$.trim($(this).find(':first').text()), $(this).attr('href')]
      });
    JS

    @boards = Hash[*boards].map{ |name, path| {name: name, path: path} }

    puts "found: #{@boards.size} boards"
  end

  def get_images!
    @boards.each do |board|
      print "[#{board[:name]}] ".green + "found "
      visit PINTEREST + board[:path]
      sleep 3

      image_urls = get_unique_links!

      # change links to big size images of max width 736px 
      board[:image_urls] = image_urls.map! {|link| link.gsub('236x', '736x')}
      puts "#{board[:image_urls].size} images"

      download_images! board
    end
  end

  def get_unique_links!
    image_links = []

      until scrolled_to_bottom?
        load_all_content!

        image_links_chunk = js <<-JS
          $('.pinUiImage img').map(function(){ return $(this).attr('src') });
        JS

        image_links.concat image_links_chunk
      end

      image_links.uniq
  end

  def download_images! board
    path = @root + 'pinterest.com' + board[:path][1..-1]
    image_urls = board[:image_urls].map(&:to_s).map(&:inspect).join(' ')
    path.mkpath
    return if image_urls.empty?
    command = <<-SH
      cd #{path.to_s.inspect} && wget -c --background #{image_urls}
    SH
    system command
  end

  def load_all_content!
      js %(window.scrollTo(0, 9999999))
      sleep 3
  end

  def scrolled_to_bottom?
    js <<-JS
      $(window).scrollTop() == $(document).height() - $(window).height()
    JS
  end

  def js *args
    page.evaluate_script *args
  end

end

BackupPinterest.new.backup!
