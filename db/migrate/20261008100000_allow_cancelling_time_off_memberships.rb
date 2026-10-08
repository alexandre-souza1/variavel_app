class AllowCancellingTimeOffMemberships < ActiveRecord::Migration[7.1]
  def change
    add_column :time_off_memberships, :cancelled_at, :datetime
    remove_index :time_off_memberships, name: 'time_off_current_driver', column: [:time_off_schedule_id, :driver_id], unique: true, where: 'ends_on IS NULL AND driver_id IS NOT NULL'
    remove_index :time_off_memberships, name: 'time_off_current_helper', column: [:time_off_schedule_id, :ajudante_id], unique: true, where: 'ends_on IS NULL AND ajudante_id IS NOT NULL'
    add_index :time_off_memberships, [:time_off_schedule_id, :driver_id], unique: true, name: 'time_off_current_driver', where: 'ends_on IS NULL AND driver_id IS NOT NULL AND cancelled_at IS NULL'
    add_index :time_off_memberships, [:time_off_schedule_id, :ajudante_id], unique: true, name: 'time_off_current_helper', where: 'ends_on IS NULL AND ajudante_id IS NOT NULL AND cancelled_at IS NULL'
  end
end
