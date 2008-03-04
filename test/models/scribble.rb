class Scribble < ActiveRecord::Base
  belongs_to :scribbler, :class_name => 'Person'
  belongs_to :notebook
  
  ## Permissions ##
  createable_by_owner_of_my_notebook
  #destroyable_as_my_notebook  #Can be destroyed by anyone who can destroy my notebook
  #destroyable_by_my_scribbler
  #################
end