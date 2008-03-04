class Page < ActiveRecord::Base
  belongs_to :notebook
  has_many :words
  
  ## Permissions ##
  createable_by_owner_of_my_notebook
  updateable_by_scribblers_of_my_notebook
  readable_as_my_notebook
  #################
end