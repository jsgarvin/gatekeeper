class CoffeeMug < ActiveRecord::Base
  belongs_to :person
  
  ## Permissions ##
  crudable_by_admin
  crudable_by_my_owner
  #################
  
  #######
  private
  #######
  def set_default_owner; self.owner = Person.current unless self.owner; end
  
end