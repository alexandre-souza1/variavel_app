require "test_helper"

class ChecklistTracking::NameMatcherTest < ActiveSupport::TestCase
  setup do
    @person = Employee.create!(nome: "Alexandre de Souza Lopez", matricula: "MATCH-01")
  end

  test "recognizes unaccented abbreviated surnames and registered previous names" do
    matcher = ChecklistTracking::NameMatcher.new([@person])
    match = matcher.call(name: "  ALEXANDRE   LOPEZ ")
    assert_equal @person, match.employee
    assert match.certain?
    @person.employee_names.create!(name: "Alexandre da Silva")
    match = ChecklistTracking::NameMatcher.new([@person]).call(name: "Alexandre da Silva")
    assert match.certain?
    assert_equal @person, match.employee
  end

  test "does not select a person when an abbreviation matches multiple employees" do
    other = Employee.create!(nome: "Alexandre Roberto Lopez", matricula: "MATCH-02")
    match = ChecklistTracking::NameMatcher.new([@person, other]).call(name: "Alexandre Lopez")
    assert_nil match.employee
    assert_equal :ambiguous, match.confidence
  end

  test "a unique first name remains a suggestion rather than a certain match" do
    match = ChecklistTracking::NameMatcher.new([@person]).call(name: "Alexandre")
    assert_equal @person, match.employee
    assert_not match.certain?
  end

  test "a small spelling error is suggested without automatic attribution" do
    @person.update!(nome: "Alexandre Lopez")
    match = ChecklistTracking::NameMatcher.new([@person]).call(name: "Alexandre Lopes")
    assert_equal @person, match.employee
    assert_equal :similar, match.confidence
    assert_not match.certain?
  end

  test "several names in free text require review" do
    other = Employee.create!(nome: "Carlos da Silva", matricula: "MATCH-03")
    match = ChecklistTracking::NameMatcher.new([@person, other]).call(text: "Alexandre de Souza Lopez e Carlos da Silva não fizeram o checklist")
    assert_nil match.employee
    assert_equal :ambiguous, match.confidence
  end
end
