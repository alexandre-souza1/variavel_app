require "test_helper"

class LabelContrastTest < ActiveSupport::TestCase
  include ApplicationHelper

  test "dark labels use white and light labels use black independently of the theme" do
    assert_equal "#ffffff", label_text_color("#3420a8")
    assert_equal "#ffffff", label_text_color("#000000")
    assert_equal "#000000", label_text_color("#ffffff")
    assert_equal "#000000", label_text_color("#15c6dd")
    assert_equal "#000000", label_text_color("#9699be")
  end

  test "shorthand colors and legacy invalid colors are handled" do
    assert_equal "#ffffff", label_text_color("#000")
    assert_equal "#000000", label_text_color("#FFF")
    assert_equal "#ffffff", label_text_color(nil)
    assert_equal "#ffffff", label_text_color("MyString")
  end
end
