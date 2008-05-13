class UpdatePermission < ActiveRecord::Base
  belongs_to :updater, :class_name => 'Person'
  belongs_to :notebook
  
  ## Permissions ##
  creatable_by_owner_of_my_notebook
  #################
end