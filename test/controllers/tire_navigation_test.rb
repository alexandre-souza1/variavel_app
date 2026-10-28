require "test_helper"

class TireNavigationTest < ActionDispatch::IntegrationTest
  test "Pneus and Frota follow the same visibility rules for every role and sector" do
    user = users(:one)
    User.roles.each_key do |role|
      User.sectors.each_key do |sector|
        user.update!(role: role, sector: sector)
        get tire_schedule_path
        assert_response :success
        visible = role == "admin" || (role != "mechanical" && %w[fleet du safety].include?(sector))
        count = visible ? 1 : 0
        %w[#fleetDropdown #fleetTiresHeading [aria-controls=mobileFleetCollapse] #mobileFleetTiresHeading].each do |selector|
          assert_select selector, count: count, message: "#{role}/#{sector}: #{selector}"
        end
      end
    end
  end

  test "Pneus is a group inside Frota on desktop and mobile with only report destinations" do
    get tire_schedule_path
    assert_response :success
    assert_select "#fleetTiresHeading", text: "Pneus"
    assert_select "#mobileFleetTiresHeading", text: "Pneus"
    assert_select "h1 i.mdi.mdi-tire"
    assert_select "#tiresDropdown, #mobileTiresCollapse", count: 0
    destinations = [tire_schedule_path, tire_inspections_path, tire_pressure_path]
    destinations.each do |path|
      assert_select ".dropdown-menu[aria-labelledby=fleetDropdown] a.tire-nav-link[href=?]", path, count: 1
      assert_select "#mobileFleetCollapse a.tire-nav-link[href=?]", path, count: 1
    end
    assert_select "#mobileFleetCollapse a.tire-nav-link", count: 3
    assert_select ".tire-module-card", count: 0
    assert_select ".app-mobile-shortcuts a[href=?]", tire_dashboard_path, count: 0
    assert_select "#navbarMain > ul > a[href=?]", tire_dashboard_path, count: 0
  end
end
