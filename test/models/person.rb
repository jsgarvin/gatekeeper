require 'notebook'
require 'page'
require 'role'
require 'scribble'
require 'word'

class Person < ActiveRecord::Base
  has_many :notebooks, :foreign_key => 'owner_id'
  has_and_belongs_to_many :roles
  
  ##### Permissions #####
  crudable_by_admin
  createable_by_guest :unless => lambda {|new_user| new_user.is_guest? }
  readable_by_anyone
  updateable_by_self :unless => :is_guest?
  #######################
  
  class << self
    def current; @current_user ||= Person.new(:username => 'guest'); end
    def current=(u); @current_user = u; end
  end
  
  def is_admin?; username == 'administrator'; end
  def is_guest?; self.username == 'guest'; end
  def is_anyone?; true; end
  
end