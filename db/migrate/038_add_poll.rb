class AddPoll < ActiveRecord::Migration
  def self.up
    create_table :polls, :options => 'ENGINE=InnoDB DEFAULT CHARSET=utf8' do |t|
      t.column :title,  :string, :limit => 120, :null => false
      t.column :close_date, :date, :null => false
      t.column :lock_version, :integer, :default => 0
      t.timestamps
    end
  end

  def self.down
    drop_table :polls
  end
end
