module GateKeeper
  
  class << self
    
    ############################################
    #:section: GateKeeper Configuration Options
    ############################################
    
    #Set the class for tracking logged in users. Defaults to 'User' if not set.
    def user_class_name=(string); @gate_keeper_user_class_name = string; end
    def user_class #:nodoc:
      return (@gate_keeper_user_class_name ||= 'User').constantize
    end
    
    ############################################
    #:section: Enabling and Disabling GateKeeper
    ############################################
    
    #Turns permission checking on or off indefinitely. Defaults to on. 
    #Set to false in config/environment.rb to turn GateKeeper off for
    #the entire application. 
    #
    #You can use bypass and with_permission_checking methods for temporary switches.
    def enabled=(boolean); @enabled = boolean; end
    
    #Returns false if permission checking is currently turned off. Defaults to true.
    def enabled?; @enabled = @enabled.nil? ? true : @enabled; end
    
    #Temporarily disables permission checking to execute passed block.
    #Resets permission checking to previous setting at completion.
    #
    #bypass is an alias for without_permission_checking
    def bypass(&blk); wrap_enabling(false,&blk); end
    alias_method :without_permission_checking, :bypass
    
    #Temporarily enables permission checking to execute passed block.
    #Resets permission checking to previous setting at completion.
    def with_permission_checking(&blk); wrap_enabling(true,&blk); end   
    
    #############################
    #:section: Permission Scoping
    #############################

    #Permission scoping allows ActiveRecord finder methods that return
    #arrays of matching objects to quietly eliminate any objects that
    #User.current doesn't have permission to read, and return the
    #remaining objects.
    #
    #By default, permission scoping is disabled and finder methods will
    #raise a GateKeeper::PermissionError when they find an object that
    #User.current doesn't have permission to read.
    #
    #To globally enable permission scoping for the application, set
    # GateKeeper.permission_scoping_enabled = true
    #in your environment.rb 
    def permission_scoping_enabled=(boolean); @permission_scoping_enabled = boolean; end
    
    #Returns true if permission scoping is enabled. Defaults to false.
    #See permission_scoping_enabled= for more information on permission
    #scoping. 
    def permission_scoping_enabled?; @permission_scoping_enabled; end
    
    #Temporarily enable permission scoping to execute the passed block.
    #Permission scoping is reset back to previous state at completion.
    #
    #See permission_scoping_enabled= for more information on permission
    #scoping. 
    def with_permission_scoping(&blk); wrap_permission_scoping(true,&blk); end
    
    #Temporarily disable permission scoping to execute the passed block.
    #Permission scoping is reset back to previous state at completion.
    #
    #See permission_scoping_enabled= for more information on permission
    #scoping. 
    def without_permission_scoping(&blk); wrap_permission_scoping(false,&blk); end
    
    #####################################
    # Making Mountains Out Of Molehills #
    #####################################
    
    def raise_permission_error(method,obj) #:nodoc:
      raise(GateKeeper::PermissionError, "#{method.to_s.titleize} Denied by GateKeeper for #{obj.inspect} by #{GateKeeper.user_class.current.inspect}")
    end
    
    #######
    private
    #######
    
    def wrap_enabling(bool,&blk)
      previously_enabled = self.enabled?
      begin
        self.enabled = bool
        yield
      ensure
        self.enabled = previously_enabled
      end
    end
    
    def wrap_permission_scoping(bool,&blk)
      previously_scoping = permission_scoping_enabled?
      begin
        self.permission_scoping_enabled = bool
        yield
      ensure
        self.permission_scoping_enabled = previously_scoping
      end
    end
  end
  
  #GateKeeper::ClassMethods are automatically mixed into all ActiveRecord classes.
  module ClassMethods
    
    ##################################
    #   Class Anchor Chain Methods   #
    # (All Class Chains Start Here.) #
    ##################################
    
    #Returns true if User.current has full CRUD permissions
    #on all instances of base class.
    def crudable?; return !GateKeeper.enabled?; end
    
    #Returns true if User.current has permission to create
    #instances of base class.
    def creatable?; return crudable?; end
    
    ##############################################
    # Methods to permit users to RUD themselves. #
    #      Meaningless in non-user classes.      #
    ##############################################
    
    #When set in the User class, allows users to 
    #read themselves. You'll probably want to set either
    #readable_by_all or readable_by_self for users, otherwise
    #they'll have dificulty even logging in.
    def readable_by_self; chain_self_method(:readable); end
    
    #When set in the User class, allows users to 
    #update their own records.
    def updatable_by_self(opts = {}); chain_self_method(:updatable,opts); end
    
    #When set in the User class, allows users to commit virtual suicide.
    #You probably do NOT want to set this, but it's here anyway.
    def destroyable_by_self; chain_self_method(:destroyable); end
    
    def method_missing( method_sym, *args, &block ) #:nodoc:
      super unless method_sym.to_s[/^(crudable|creatable|readable|updatable|destroyable|)_(by|as)_(.*)/]
      permission = $1; preposition = $2; suffix = $3
      opts = args.shift || {}
      association_chain = suffix.split(/_of_/);
      is_not_association = !association_chain.last[/my_/] #check User class instead of object associations
      method_chain_suffix = "#{preposition}_#{suffix}_check"
      
      if is_not_association and preposition == 'by' and permission[/(crudable|creatable)/]
         
        #Add link to *Class* method chain
        meta_eval do
          define_method("creatable_with_#{method_chain_suffix}?") do
            return true if send("creatable_without_#{method_chain_suffix}?")
            unless GateKeeper.user_class.current.respond_to?('has_gate_keeper_role?')
              GateKeeper.user_class.send(:include,GateKeeper::DefaultUserRoleCheckMethod) 
            end
            GateKeeper.user_class.current.has_gate_keeper_role?(suffix)
          end
          alias_method_chain "creatable?", method_chain_suffix
        end
      
      end
      
      #If we're in a crudable_as_* scenario, chain onto all of the CRUD methods.
      permits = (preposition == 'as' and permission == 'crudable') ? ['crudable','creatable','readable','updatable','destroyable'] : [permission]
      permits.each do |permit|
        
        #Add link to *Instance* method chain
        define_method("#{permit}_with_#{method_chain_suffix}?") do
          return true if send("#{permit}_without_#{method_chain_suffix}?")
          
              ### Check current user against User class is_<role>? ###
              ### method if passed <permit>_by_<role>              ###
            if is_not_association
              unless GateKeeper.user_class.current.respond_to?('has_gate_keeper_role?')
                GateKeeper.user_class.send(:include,GateKeeper::DefaultUserRoleCheckMethod) 
              end
              return (GateKeeper.user_class.current.has_gate_keeper_role?(suffix) and process_permission_options?(opts))
            end
              ### Otherwise, check association chain for current user ###
          
          #Copy association chain since we might need to use it more than once.
          chain_copy = association_chain.dup
          #Pull this objects immediate association from the chain
          associated = self.send(chain_copy.pop.gsub(/^my_/,''))
          
          #Follow the yellow brick road
          final_associated = follow_permission_association_chain(associated,chain_copy)
          first_check = case preposition
            when 'by' : [final_associated].flatten.include?(GateKeeper.user_class.current)
            when 'as' : final_associated ? final_associated.send(permit+'?') : false
          end
          return (first_check and process_permission_options?(opts)) 
        end
        alias_method_chain "#{permit}?", method_chain_suffix
      end
      
    end
    
    def self.extended(base) #:nodoc:
      base.class_eval do
        class << self
          alias_method_chain :find, :gate_keeper
          alias_method_chain :find_every, :gate_keeper_scoping
          alias_method_chain :find_initial, :gate_keeper_permission_check
        end
      end
    end
    #######
    private
    #######
    
    def chain_self_method(method,opts = {})
      define_method("#{method}_with_self_check?") do
        return true if send("#{method}_without_self_check?")
        return true if GateKeeper.user_class.current == self and process_permission_options?(opts)
      end
      alias_method_chain "#{method}?", 'self_check'
    end
    
    def find_with_gate_keeper(*args)
      results = GateKeeper.bypass { find_without_gate_keeper(*args) }
      readable_method = GateKeeper.permission_scoping_enabled? ? 'readable?': 'raise_unless_readable'
      if results.respond_to?(:delete_if)
        results.delete_if{|x| !x.send(readable_method)}
      else
        if args.first.is_a?(Symbol)
          return nil unless (results and results.readable?) 
        else
          GateKeeper.raise_permission_error(:read,results) unless (results and results.readable?)
        end
      end
      
      includes = nil
      args.each do |a|
        if a.is_a?(Hash) and a.keys.include?(:include)
          includes = a[:include]
        end
      end
      traverse_eagerly_loaded_associations(results,includes,readable_method) if includes
      return results
    end
    
    def find_every_with_gate_keeper_scoping(*args)
      #provides scoping for find(:all), find_all_by(:title => 'title'), etc.
      results = GateKeeper.bypass { find_every_without_gate_keeper_scoping(*args) }
      readable_method = GateKeeper.permission_scoping_enabled? ? 'readable?': 'raise_unless_readable'
      results.delete_if{|x| !x.send(readable_method)}
      return results
    end
    
    def find_initial_with_gate_keeper_permission_check(*args)
      #provides permssion checking for find_by_etc() convenience methods.
      result = GateKeeper.bypass { find_initial_without_gate_keeper_permission_check(*args) }
      return nil unless (result and result.readable?) 
      #GateKeeper.raise_permission_error(:read,result) unless (result.nil? or result.readable?)
      return result
    end
    
    #Traverse and check readablility of eagerly loaded associations
    def traverse_eagerly_loaded_associations(things,includes,readable_method)
      things = [things] unless things.is_a?(Array) 
      things.each do |thing|
        Array([includes]).each do |include|
          if include.is_a?(Hash)
            include.keys.each do |key|
              traverse_eagerly_loaded_associations(thing.send(key),include[key],readable_method)
            end
          elsif include.is_a?(Array)
            include.each {|i| thing.send(i).delete_if {|x| !x.send(readable_method) }}
          else
            if thing.send(include).is_a?(Array)
              thing.send(include).delete_if{|x| !x.send(readable_method) }
            else
              thing.send(include).send(readable_method) unless thing.send(include).nil?
            end
          end
        end
      end
    end
    
    #Borrowed from _why's "Seeing Metaclasses Clearly" : http://www.whytheluckystiff.net/articles/seeingMetaclassesClearly.html
    def metaclass; class << self; self; end; end
    def meta_eval(&blk); metaclass.instance_eval(&blk); end
      
    
  end
  
  #GateKeeper::InstanceMethods are automatically mixed into all ActiveRecord classes.
  module InstanceMethods
    
    #Setup Callbacks
    def self.included(base) #:nodoc:
      base.before_create :raise_unless_creatable
      base.before_update :raise_unless_updatable
      base.before_destroy :raise_unless_destroyable
    end
    
    #########################################
    #     Instance Anchor Chain Methods.    #
    #   (All Instance Chains Start Here.)   #
    #########################################
    
    #Returns true if User.current has full CRUD permissions on
    #this instance of base class.
    def crudable?; return !GateKeeper.enabled?; end
      
    #Returns true if User.current has permission to create
    #new instance of base class. 
    def creatable?; crudable?; end
      
    #Returns true if User.current has read permissions on
    #this instance of base class. 
    def readable?; crudable?; end
    
    #Returns true if User.current has update permissions on
    #this instance of base class. 
    def updatable?; crudable?; end
      
    #Returns true if User.current has destroy permissions on
    #this instance of base class. 
    def destroyable?; crudable?; end
    
    #Raise a GateKeeper::PermissionError unless User.current
    #has permission to create new instances of base class.
    def raise_unless_creatable; raise_unless(:create); end
    
    #Raise a GateKeeper::PermissionError unless User.current
    #has permission to read this instance of base class.
    def raise_unless_readable; raise_unless(:read); end
    
    #Raise a GateKeeper::PermissionError unless User.current
    #has permission to update this instance of base class.
    def raise_unless_updatable; raise_unless(:update); end
    
    #Raise a GateKeeper::PermissionError unless User.current
    #has permission to destroy instance of base class.
    def raise_unless_destroyable; raise_unless(:destroy); end
    
    def raise_unless(method) #:nodoc:
      self.send("#{method.to_s.gsub(/e$/,'')}able?") ? true : GateKeeper.raise_permission_error(method,self)
    end
  
    #######
    private
    #######
    
    def follow_permission_association_chain(associated,array)
      case array.length
        when 0 : return associated
        when 1 : return associated.send(array.pop)
        else return follow_permission_association_chain(associated.send(array.pop),array)
      end
    end
    
    #Process :if and :unless options and return accordingly
    def process_permission_options?(opts)
      if opts[:if]
        case
          when opts[:if].is_a?(Symbol) : return self.send(opts[:if])
          when opts[:if].is_a?(Proc) : return opts[:if].call(self)
          else return false #got :if option, but didn't recognize type
        end  
      elsif opts[:unless]
        case
          when opts[:unless].is_a?(Symbol) : return !self.send(opts[:unless])
          when opts[:unless].is_a?(Proc) : return !opts[:unless].call(self)
          else return false #got :unless, option, but dind't recognize type
        end
      end
      return true  #didn't get extra conditions to process
    end
  end
  
  module DefaultUserRoleCheckMethod
    
    #This method is automatically included into your User class. GateKeeper calls this method
    #and passes the name of a role from a declared permission as an argument. For instance, if
    #a class is #+updatable_by_moderator+, then GateKeeper will be calling 
    #has_gate_keeper_role?('moderator') on your User class. Override this method with your own
    #if the following isn't appropriate for your purposes.
    #
    #==== is_<role_name>?
    #has_gate_keeper_role? first looks for an instance method in the form of 'is_<role_name>?',
    #(eg. 'is_moderator?') and checks if it returns true on the current user. 
    #Otherwise, it will fall through to roles association check.
    #
    #==== Roles Table.
    #Asuming you have a +roles+ table with a +name+ column, and your User class has_many :roles,
    #has_gate_keeper_role? will return true if the user has a role with the name passed.
    #
    def has_gate_keeper_role?(role_name)
      @has_gate_keeper_role ||= {}
      return @has_gate_keeper_role[role_name] if @has_gate_keeper_role[role_name]
      return @has_gate_keeper_role[role_name] = true if (respond_to?("is_#{role_name}?") and send("is_#{role_name}?"))
      return @has_gate_keeper_role[role_name] = true if (respond_to?(:roles) and roles.find_by_name(role_name))
      return @has_gate_keeper_role[role_name] = false
    end
  end
  
  #Indicates that the currently logged in user doesn't have permission to perform
  #the requested CRUD action on the associated object.
  class PermissionError < RuntimeError; end
end

ActiveRecord::Base.extend GateKeeper::ClassMethods
ActiveRecord::Base.send :include, GateKeeper::InstanceMethods