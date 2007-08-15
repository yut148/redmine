class InsertBuiltinRoles < ActiveRecord::Migration
  def self.up
    nonmember = Role.new(:name => 'Non member', :position => 0)
    nonmember.builtin = 1
    nonmember.save
    
    anonymous = Role.new(:name => 'Anonymous', :position => 0)
    anonymous.builtin = 2
    anonymous.save  
  end

  def self.down
    Role.destroy_all 'builtin <> 0'
  end
end
