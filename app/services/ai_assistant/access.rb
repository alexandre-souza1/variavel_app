module AiAssistant
  # Uses the same module permissions and record scopes as the app screens.
  class Access
    include NavbarHelper

    def initialize(user)
      @user = user
    end

    def allowed?(area)
      return false unless @user&.active?
      return true if @user.admin?
      return %i[tasks documents public_resources checklists].include?(area) if @user.mechanical?

      case area
      when :tasks, :documents, :public_resources, :checklists then true
      when :finance then can_view_nav_link?(:finance, @user)
      when :employees then @user.can_view_employees?
      when :du, :time_off, :consumption then @user.can_view_du_operations?
      when :employee_schedules then @user.can_view_du_operations? && @user.can_view_employees?
      when :az then @user.can_access_az_dashboard?
      when :routines then can_view_nav_link?(:gerot, @user)
      when :meetings then true # Each record also requires its plan and meeting access.
      when :plates then can_view_subitem?(:plates, @user)
      when :availability, :dimensioning then can_view_nav_link?(:availability, @user)
      when :tires then can_view_nav_link?(:tires, @user)
      when :stress then can_view_nav_link?(:stress_test, @user)
      when :pcd then @user.sector_du?
      when :admin then false
      else false
      end
    end

    def employee_sectors
      @user.employee_sectors
    end

    def employees
      return Employee.none unless allowed?(:employees)
      @user.admin? ? Employee.all : Employee.visible_to(@user)
    end

    def invoices
      allowed?(:finance) ? Invoice.visible_to(@user) : Invoice.none
    end

    def meetings
      allowed?(:meetings) ? MeetingMinute.visible_to(@user) : MeetingMinute.none
    end
  end
end
