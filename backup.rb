#!/usr/bin/env ruby
# encoding: utf-8

require 'capybara'
require 'capybara/dsl'
require 'pry'
require 'pp'
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

  def backup!
    login!
    get_list_of_boards!
    get_images!
  end

  private

  def usage!
    warn "backup username email password [destination]"
    exit!
  end

  def login!
    puts "Logging in as #{@username} (#{@email})"
    visit PINTEREST + '/login'
    fill_in 'email', with: @email
    fill_in 'password', with: @password
    click_button 'Login'
  end

  def get_list_of_boards!
    puts "getting list of boards…"
    visit PINTEREST + @username
    boards = js <<-JS
      $('#ColumnContainer > ul > li h3 a').map(function(){
        return [$(this).text(), $(this).attr('href')]
      });
    JS
    @boards = Hash[*boards].map{ |name, path| {name: name, path: path} }

    puts "found: #{@boards.size} boards"
  end

  def get_images!
    @boards.each do |board|
      print "[#{board[:name]}] ".green + "found "
      visit PINTEREST + board[:path]
      load_all_content!
      board[:image_urls] = js <<-JS
        $('.pin').map(function(){ return $(this).data('closeup-url') });
      JS
      puts "#{board[:image_urls].size} images"
      download_images! board
    end
  end

  def download_images! board
    path = @root + 'pinterest.com' + board[:path][1..-1]
    image_urls = board[:image_urls].map(&:to_s).map(&:inspect).join(' ')
    path.mkpath
    return if image_urls.empty?
    command = <<-SH
      cd #{path.to_s.inspect} && wget --quiet --background #{image_urls}
    SH
    # puts command
    system command
  end

  def load_all_content!
    while !scrolled_to_bottom?
      js %(window.scrollTo(0, 9999999))
      sleep 1
    end
  end

  def scrolled_to_bottom?
    js <<-JS
      $('html').height() - document.body.scrollTop <= $(window).height()
    JS
  end


  def js *args
    page.evaluate_script *args
  end

end

BackupPinterest.new.backup!
