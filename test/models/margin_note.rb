class MarginNote < ActiveRecord::Base
  belongs_to :page
  
  ## Permissions ##
  crudable_by_owner_of_notebook_of_my_page
  #################
end