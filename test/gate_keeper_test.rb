$: << File.expand_path(File.dirname(__FILE__) + "/models")
require 'test/unit'
require 'rubygems'
gem 'activerecord', '>= 2.0.2'
require 'active_record'
require "#{File.dirname(__FILE__)}/../init"
require 'person'

ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :dbfile => ":memory:")

class GateKeeperTest < Test::Unit::TestCase
  def setup
    setup_db
    
    #Change user class from default 'User'.
    GateKeeper.user_class_name = 'Person'
    
    #Bypass GateKeeper to setup initial stuff. 
    GateKeeper.bypass do
      @admin = Person.create(:username => 'administrator')
      @arthur = Person.create(:username => 'arthur')
      @amy = Person.create(:username => 'amy')
      @arthurs_book = Notebook.create(:title => "Arthur's Book", :owner => arthur)
      @arthurs_book.pages.create(:number => 1)
      @amys_book = Notebook.create(:title => "Amys Book", :owner => amy)
      
    end
  end
  
  def teardown; teardown_db; end
  
  def admin; @admin; end
  def arthur; @arthur; end
  def amy; @amy; end
  def find_arthurs_book; Notebook.find(@arthurs_book.id); end
  def find_amys_book; Notebook.find(@amys_book.id); end
  def find_arthurs_book_with_eager_loading
    Notebook.find(:first,
      :conditions => ['notebooks.id = ?',@arthurs_book.id],
      :include => {:pages => [:margin_notes, :coffee_stains] }
    )
  end
    
  def test_user_permissions
    #### Login as Guest ###
    Person.current = nil
    assert_equal('guest',Person.current.username)
    assert(Person.current.new_record?)
    assert(Person.current.is_guest?)
    
    #Guest can't save herself
    assert_raise(GateKeeper::PermissionError) { Person.current.save }
    
    #### Login as Admin ####
    Person.current = admin
    
    #Admin can create new users.
    newbie = Person.create(:username => 'newbie')
    assert(newbie.id > 1)
    
    #Admin can destroy users
    assert(newbie.destroy)

    #### Login as Arthur ####
    Person.current = arthur
    
    #Arthur can not create new users
    assert_raise(GateKeeper::PermissionError) { Person.create(:username => 'nobody') }

    #Arthur can not destroy users
    assert_raise(GateKeeper::PermissionError) { amy.destroy }
  
    #Arthur can read himself
    assert_equal(arthur,Person.find(arthur.id))
    
    #Arthur can update himself
    assert_equal(nil,arthur.hair_color)  
    arthur.update_attributes(:hair_color => 'red')
    arthur.reload
    assert_equal('red',arthur.hair_color) 
    
    #Arthur can read amy
    assert_equal('amy',amy.username)
    
    #Arthur can not update amy
    assert_equal(nil,amy.hair_color)  
    assert_raise(GateKeeper::PermissionError) { amy.update_attributes(:hair_color => 'green') }
    amy.reload
    assert_equal(nil,amy.hair_color)
  end
  
  def test_notebook_permissions
    #### Login as Admin ####
    Person.current = admin
    
    # Admin can create notebooks for other users.
    assert(Notebook.create(:title => 'A Notebook For Amy', :owner => amy))
    
    #### Login as Arthur ####
    Person.current = arthur
    
    # Arthur can read his own books
    assert_equal("Arthur's Book",find_arthurs_book.title)
    
    # Arthur can create notebooks for himself
    arthurs_new_book = Notebook.create(:title => 'My New Book')
    assert_equal(arthurs_new_book.owner,arthur)
  
    #Arthur can update his book
    assert(find_arthurs_book.update_attributes(:title => 'Bumbleweed'))
  
    #Arthur can not create notebooks for amy
    assert_raise(GateKeeper::PermissionError) { Notebook.create(:title => 'A Notebook For Amy', :owner => amy) }
    
    #Arthur can't find Amy's notebook
    assert_raise(GateKeeper::PermissionError) { find_amys_book }
    
    #Check other convenience methods. Should only find things with readable permissins
    assert_equal(nil,Notebook.find(:first, :conditions => ['title = ?',@amys_book.title]))
    assert_raise(GateKeeper::PermissionError) { Notebook.find(:all, :conditions => ['title = ?',@amys_book.title]) }
    assert_equal([],GateKeeper.with_permission_scoping { Notebook.find(:all, :conditions => ['title = ?',@amys_book.title])})
    assert_equal(nil,Notebook.find_by_title(@amys_book.title))
    assert_raise(GateKeeper::PermissionError) { Notebook.find_all_by_title(@amys_book.title) }
    assert_equal([],GateKeeper.with_permission_scoping { Notebook.find_all_by_title(@amys_book.title) })
    
    arthurs_book_clone1 = Notebook.find_or_create_by_title(find_arthurs_book.title)
    assert_equal(find_arthurs_book,arthurs_book_clone1)
    arthurs_book2 = Notebook.find_or_create_by_title(@amys_book.title)
    assert_not_equal(find_arthurs_book,arthurs_book2)
    assert_equal(arthur,arthurs_book2.owner)
    
    arthurs_book_clone2 = Notebook.find_or_initialize_by_title(find_arthurs_book.title)
    assert_equal(find_arthurs_book,arthurs_book_clone2)
    assert(!arthurs_book_clone2.new_record?)
    arthurs_book3 = Notebook.find_or_initialize_by_title(@amys_book.title)
    assert_not_equal(find_arthurs_book,arthurs_book3)
    assert(arthurs_book3.new_record?)
    
    #Arthur can destroy his own book.
    pre_book_count = arthur.notebooks.size
    assert(find_arthurs_book.destroy)
    assert_equal(pre_book_count-1,arthur.notebooks.size)
    
    #### Login as Admin ####
    Person.current = admin
    
    #Admin can destroy other people books
    pre_book_count = Notebook.count()
    assert(arthurs_book2.destroy)
    assert_equal(pre_book_count-1,Notebook.count())
  end
  
  def test_update_permissions
    #### Login as Arthur ####
    Person.current = arthur
    
    # Arthur can add Amy as an updater to his book
    find_arthurs_book.updaters << amy
    assert(find_arthurs_book.updaters.include?(amy))
    
    # Arthur can not see Amy's book
    assert_raise(GateKeeper::PermissionError) { find_amys_book }
    
    #### Login as Amy ####
    Person.current = amy
    
    #As a scribbler, Amy can read Arthur's book
    assert_equal("Arthur's Book",find_arthurs_book.title)
    
    #As an updater, Amy can update Arthur's book
    assert(find_arthurs_book.update_attributes(:title => "Amy's Stolen Book"))
    assert_equal("Amy's Stolen Book",find_arthurs_book.reload.title)
    
    #Amy can remove herself as an updater
    assert(find_arthurs_book.updaters.delete(amy))
    
    #Amy can find all books, scoped to just those she's allowed to read.
    scoped_books = GateKeeper.with_permission_scoping { Notebook.find(:all) }
    assert_equal(false,scoped_books.include?(@arthurs_book))
    assert_equal(true,scoped_books.include?(@amys_book))
    
    #No longer a scribbler, now Amy can not read Arthur's Book
    assert_raise(GateKeeper::PermissionError) { find_arthurs_book }
    
  end
  
  def test_page_permissions
    #### Login as Arthur ####
    Person.current = arthur
    
    #Arthur can read pages in his book
    assert_equal(1,find_arthurs_book.pages.first.number)
    
    #Arthur can add pages to his book
    assert(find_arthurs_book.pages.create(:number => 2))
    
    # Arthur adds Amy as a updater to his book
    find_arthurs_book.updaters << amy
    
    #### Login as Amy ####
    Person.current = amy
    #Amy can read pages in Arthur's Book
    assert_equal(1,find_arthurs_book.pages.first.number)
    
    #Arthur can NOT add pages to Arthur's book
    assert_raise(GateKeeper::PermissionError) { find_arthurs_book.pages.create(:number => 314159) }
    
    #Amy can update pages in Arthur's Book
    assert(find_arthurs_book.pages.first.update_attributes(:number => 42))
    assert_equal(42,find_arthurs_book.pages.first.number)
    
    #Amy can remove herself as a scribbler
    assert(find_arthurs_book.updaters.delete(amy))
    
    #No longer a scribbler, now Amy can not find pages in Arthur's Book
    page_id = GateKeeper.bypass { @arthurs_book.pages.first.id }
    assert_raise(GateKeeper::PermissionError) { Page.find(page_id) }
  end
  
  def test_chained_of_permissions_from_word
    #### Login as Arthur ####
    Person.current = arthur
    
    #Arthur can add words to pages to his book
    assert(find_arthurs_book.pages.first.words.create(:text => 'Hello'))
    
    #Arthur can read words on pages in his book.
    assert_equal('Hello',find_arthurs_book.pages.first.words.first.text)
    
    #Arthur can update words on pages in his book
    assert(find_arthurs_book.pages.first.words.first.update_attributes(:text => 'World'))
    assert_equal('World',find_arthurs_book.pages.first.words.first.text)
    
    #Arthur can destroy words on pages in his book
    pre_word_count = Word.count()
    assert(find_arthurs_book.pages.first.words.first.destroy)
    assert_equal(pre_word_count-1,Word.count())
    
    # Arthur adds Amy as a updater to his book
    find_arthurs_book.updaters << amy
    
    #### Login as Amy ####
    Person.current = amy
    
    #Amy can add words to pages to Arthur's book
    assert(find_arthurs_book.pages.first.words.create(:text => 'Hello'))
    
    #Amy can read words on pages in Arthur's book.
    assert_equal('Hello',find_arthurs_book.pages.first.words.first.text)
    
    #Amy can update words on pages in Arhtur's book
    assert(find_arthurs_book.pages.first.words.first.update_attributes(:text => 'World'))
    assert_equal('World',find_arthurs_book.pages.first.words.first.text)
    
    #Amy can destroy words on pages in Arthur's book
    pre_word_count = Word.count()
    assert(find_arthurs_book.pages.first.words.first.destroy)
    assert_equal(pre_word_count-1,Word.count())
    
    #Amy adds another word to a page in Arthur's book
    page = find_arthurs_book.pages.first
    extra = find_arthurs_book.pages.first.words.create(:text => 'Extra')
    extra.reload #reset associations and force reload of associations after Amy unscribbles herself
    
    #Amy removes herself as an updater
    assert(find_arthurs_book.updaters.delete(amy))
    
    #Amy can not CRUD words on Arhtur's Book
    assert_raise(GateKeeper::PermissionError) { page.words.create(:text => 'Denied') }
    assert_raise(GateKeeper::PermissionError) { Word.find(extra.id) }
    assert_raise(GateKeeper::PermissionError) { extra.update_attributes(:text => 'DeniedAgain') }
    assert_raise(GateKeeper::PermissionError) { extra.destroy }
  end
  
  def test_with_eager_loading
    #### Login as Arthur ####
    Person.current = arthur
    
    #Arthur can add words to pages to his book
    assert(find_arthurs_book.pages.first.words.create(:text => 'Hello'))
    
    #Arthur can add margin_notes to pages to his book
    assert(find_arthurs_book.pages.first.margin_notes.create(:content => 'Scratch'))
    
    # Arthur adds Amy as a updater to his book
    find_arthurs_book.updaters << amy
    
    #### Login as Amy ####
    Person.current = amy
    
    #Amy can read words on pages in Arthur's book.
    assert_equal('Hello',find_arthurs_book.pages.first.words.first.text)
    
    #Amy can NOT read Arthur's eagerly loaded margin notes.
    assert_equal([],
      GateKeeper.with_permission_scoping {
        find_arthurs_book_with_eager_loading.pages[0].margin_notes
      }
    )
    assert_raise(GateKeeper::PermissionError) { 
      find_arthurs_book_with_eager_loading
    }
    
    #### Login as Arthur ####
    Person.current = arthur
    
    #Arthur's margin note hasn't been erroneously
    #deleted from the database by GateKeeper
    assert_equal('Scratch',find_arthurs_book.pages.first.margin_notes.first.content)
  end
  
  def test_method_missing_superizer
    assert_raise(NoMethodError) { Person.non_existant_method }
  end
end

###############################
#### DB Setup and Teardown ####
###############################

def setup_db
  #Supress annoying Schema creation output when tests run
  old_stdout = $stdout
  $stdout = StringIO.new
  
  ActiveRecord::Schema.define(:version => 1) do
    create_table :people do |t|
      t.column :username, :string
      t.column :hair_color, :string
    end
    
    create_table :roles do |t|
      t.column :name, :string
    end
    
    create_table :people_roles do |t|
      t.column :role_id, :integer
      t.column :person_id, :integer
    end
    
    create_table :notebooks do |t|
      t.column :title, :string
      t.column :owner_id, :integer
      t.column :ghost_writer_id, :integer
    end
    
    create_table :update_permissions do |t|
      t.column :updater_id, :integer
      t.column :notebook_id, :integer
    end
    
    create_table :pages do |t|
      t.column :number, :integer
      t.column :notebook_id, :integer
    end
    
    create_table :margin_notes do |t|
      t.column :content, :string
      t.column :page_id, :integer
    end
    
    create_table :coffee_stains do |t|
      t.column :opacity, :integer
      t.column :page_id, :integer
    end
    
    create_table :words do |t|
      t.column :text, :string
      t.column :page_id, :integer
    end
  end
  
  #Re-enable stdout
  $stdout = old_stdout
end

def teardown_db
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table)
  end
end