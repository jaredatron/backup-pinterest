#!/usr/bin/env ruby
# encoding: utf-8

require 'capybara'
require 'capybara/dsl'
require 'pry'
require 'pathname'
require 'colored'
require 'pry-byebug'

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
    @username = ARGV.shift or usage
    @email    = ARGV.shift or usage
    @password = ARGV.shift or usage
    @root     = Pathname ARGV.shift || File.expand_path('..', __FILE__)
    @wget_logfile = Bundler.root.join('wget.log')
  end

  def usage
    warn "backup username email password [destination]"
    exit!
  end

  def backup
    login
    get_list_of_boards
    get_images
  end

  private

  def login
    puts "Logging in as #{@username} (#{@email})"
    visit PINTEREST + '/login'
    fill_in 'username_or_email', with: @email
    fill_in 'password', with: @password
    page.find("[type=submit]").click
  end

  def get_list_of_boards
    visit PINTEREST + @username
    # need to wait for boards loaded
    sleep 5

    puts "getting list of boards…"

    boards = js <<-JS
      jQuery('.UserBoards .Board > a').map(function(){
        return [jQuery.trim(jQuery(this).find('.boardName .boardRepTitle .title').text()), jQuery(this).attr('href')]
      });
    JS

    @boards = Hash[*boards].map{ |name, path| {name: name, path: path} }

    puts "found: #{@boards.size} boards"
  end

  def get_images
    @boards.each do |board|
      puts "scraping #{board[:name].to_s.inspect}".green
      visit PINTEREST + board[:path]
      sleep 1

      image_urls = get_unique_links

      # change links to big size images of max width 736px
      board[:image_urls] = image_urls.map! {|link| link.gsub('236x', '736x')}
      puts "found #{board[:image_urls].size} images".green

      download_images board
    end
  end

  def get_unique_links
    image_links = []

    until scrolled_to_bottom?
      load_all_content

      image_links_chunk = js <<-JS
        jQuery('.pinUiImage img').map(function(){ return jQuery(this).attr('src') });
      JS

      image_links.concat image_links_chunk
    end

    image_links.uniq
  end

  def download_images board
    path = @root + 'pinterest.com' + board[:path][1..-1]
    path.mkpath
    image_urls = board[:image_urls]
    return if image_urls.empty?
    image_urls.each do |image_url|
      command = <<-SH
        cd #{path.to_s.inspect} && wget -c -o #{@wget_logfile.to_s.inspect} --background #{image_url.to_s.inspect}
      SH
      `#{command}`
    end
    puts "downloaded #{image_urls.size} images into #{path}".green
  end

  def load_all_content
    js %(window.scrollTo(0, 9999999))
    sleep 3
  end

  def scrolled_to_bottom?
    js <<-JS
      jQuery(window).scrollTop() == jQuery(document).height() - jQuery(window).height()
    JS
  end

  def js *args
    if page.evaluate_script('typeof this.jQuery === "undefined"')
      page.execute_script Bundler.root.join('jquery.js').read
    end
    page.evaluate_script *args
  end

end

BackupPinterest.new.backup
