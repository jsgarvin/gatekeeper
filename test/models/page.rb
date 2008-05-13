class Page < ActiveRecord::Base
  belongs_to :notebook
  has_many :words
  has_many :margin_notes
  has_many :coffee_stains
  
  ## Permissions ##
  creatable_by_owner_of_my_notebook
  updatable_by_updaters_of_my_notebook
  readable_as_my_notebook
  #################
end