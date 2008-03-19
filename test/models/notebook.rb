class Notebook < ActiveRecord::Base
  belongs_to :owner, :class_name => 'Person'
  has_many :pages
  has_many :update_permissions
  has_many :updaters, :through => :update_permissions, :class_name => 'Person'
  validates_presence_of :owner
  before_validation_on_create :set_default_owner
  
  ## Permissions ##
  crudable_by_admin
  crudable_by_my_owner
  createable_by_my_owner
  readable_by_my_updaters
  updateable_by_my_updaters
  destroyable_by_my_owner
  #################
  
  #######
  private
  #######
  def set_default_owner; self.owner = Person.current unless self.owner; end
  
end