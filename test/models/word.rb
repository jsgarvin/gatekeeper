class Word < ActiveRecord::Base
  belongs_to :page
  
  ## Permissions ##
  crudable_by_scribblers_of_notebook_of_my_page
  crudable_as_notebook_of_my_page
  #################
end