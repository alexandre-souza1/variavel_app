require "test_helper"

class GeminiUsageReportTest < ActiveSupport::TestCase
  setup do
    AiApiRequest.delete_all
    @now = Time.zone.parse("2026-10-15 12:00:00")
    users(:one).update!(name: "Ana")
    users(:two).update!(name: "Bruno")
  end

  test "aggregates accounts resources models and failures with no duplicated calls" do
    record
    record(feature: "meeting", input_tokens: 200)
    record(user: users(:two), model: "gemini-3.1-flash-lite", feature: "variable_chat")
    record(status: 429)
    record(user: nil, feature: "variable_chat")
    report = GeminiUsageReport.new(now: @now)
    assert_equal 5, report.summary[:attempts]
    assert_equal 4, report.summary[:accepted]
    assert_equal 2, report.summary[:active_users]
    assert_equal 1, report.summary[:unattributed]
    assert_equal 500, report.summary[:input_tokens]
    assert_equal 1, report.summary[:rate_limited]
    rows = report.users[:rows]
    ana = rows.find { |row| row[:label] == "Ana" }
    assert_equal 2, ana[:accepted]
    assert_equal 3, ana[:attempts]
    assert_equal 300, ana[:input_tokens]
    assert_equal 1, ana[:features]["Atas de reunião"]
    assert_equal 2.0, ana[:average_seconds]
    assert rows.any? { |row| row[:label] == "Sem usuário associado" && row[:id].nil? }
  end

  test "period boundaries use Brasilia days and exclude future calls and other credentials" do
    start = @now.beginning_of_day - 6.days
    record(at: start - 1.second)
    record(at: start)
    record(at: @now + 1.second)
    record(fingerprint: "another-project")
    report = GeminiUsageReport.new(now: @now)
    assert_equal 1, report.summary[:accepted]
    assert_equal 1, report.daily_series.find { |series| series[:name] == "Assistente pessoal" }[:data]["09/10"]
    assert_equal 7, report.daily_series.first[:data].size
  end

  test "model and resource filters apply consistently to all comparisons" do
    record
    record(feature: "meeting")
    record(model: "gemini-3.1-flash-lite")
    report = GeminiUsageReport.new(now: @now, model: "gemini-3.6-flash", feature: "assistant", metric: "input_tokens")
    assert_equal 1, report.summary[:accepted]
    assert_equal 100, report.model_data["Gemini 3.6 Flash"]
    assert_equal ["Gemini 3.6 Flash"], report.model_data.keys
    assert_equal 100, report.user_chart["Ana"]
    assert_equal({ "Assistente pessoal" => 1 }, report.feature_data)
    assert_equal 100, report.daily_series.first[:data]["15/10"]
    assert_equal 1, report.users[:rows].first[:accepted]
  end

  test "unknown tokens are flagged and unknown historical identities are not inferred" do
    record(user: nil, input_tokens: nil)
    report = GeminiUsageReport.new(now: @now)
    assert_equal 1, report.summary[:missing_input]
    assert_equal 0, report.summary[:active_users]
    assert_equal({ "Sem usuário associado" => 1 }, report.user_chart)
    assert_nil report.users[:rows].first[:id]
  end

  test "user search escapes wildcards and pagination is bounded" do
    records = 21.times.map do |index|
      { email: "ai-report-#{index}@example.test", name: "Pessoa #{index}", encrypted_password: users(:one).encrypted_password }
    end
    ids = User.insert_all!(records, returning: %w[id]).rows.flatten
    ids.each { |id| record(user: User.find(id)) }
    report = GeminiUsageReport.new(now: @now)
    first = report.users
    last = report.users(page: 99)
    assert_equal 21, first[:total]
    assert_equal 20, first[:rows].size
    assert_equal 2, last[:page]
    assert_equal 1, last[:rows].size
    assert_equal 1, report.users(page: -1)[:page]
    assert_empty report.users(query: "%")[:rows]
    assert_equal 1, report.users(query: "Pessoa 20")[:total]
  end

  test "invalid filters fall back to safe defaults and empty reports render empty comparisons" do
    report = GeminiUsageReport.new(now: @now, period: "1000000", metric: "prompt", model: "invalid", feature: "invalid")
    assert_equal "7", report.period
    assert_equal "calls", report.metric
    assert_nil report.model
    assert_equal 0, report.summary[:accepted]
    assert_empty report.daily_series
    assert_empty report.user_chart
    assert_empty report.users[:rows]
  end

  test "removing an account preserves consumption metadata without its identity" do
    member = User.create!(email: "removed-ai-user@example.test", password: "password", name: "Conta temporária")
    usage = record(user: member)
    member.delete
    assert_nil usage.reload.user_id
    assert_equal 1, GeminiUsageReport.new(now: @now).summary[:accepted]
    assert_equal "Sem usuário associado", GeminiUsageReport.new(now: @now).users[:rows].first[:label]
  end

  test "collaborators and accounts are aggregated separately including matching names and ids" do
    employee = Employee.create!(nome: "Ana", matricula: "AI-REPORT")
    driver = drivers(:one)
    driver.update_columns(nome: "Ana")
    record
    record(user: nil, collaborator: employee, feature: "variable_chat")
    record(user: nil, collaborator: employee, feature: "variable_chat", status: 429)
    record(user: nil, collaborator: driver, feature: "variable_chat", input_tokens: 300)
    record(user: nil)
    report = GeminiUsageReport.new(now: @now)
    assert_equal 3, report.summary[:active_users]
    assert_equal 1, report.summary[:unattributed]
    assert_equal 4, report.summary[:accepted]
    assert_equal 600, report.summary[:input_tokens]
    assert_equal 4, report.user_chart.size
    assert_equal 4, report.user_chart.values.sum
    assert_equal 4, report.users[:total]
    row = report.users[:rows].find { |item| item[:kind] == "Colaborador" }
    assert_equal "Ana", row[:label]
    assert_equal 2, row[:attempts]
    assert_equal 1, row[:accepted]
    assert_equal 1, row[:rate_limited]
    assert_equal 1, row[:features]["Chat de variável"]
    assert_equal 3, report.users(query: "Ana")[:total]
    assert_empty report.users(query: "%")[:rows]
    assert_equal 2, GeminiUsageReport.new(now: @now, feature: "variable_chat").summary[:active_users]
  end

  test "all legacy profiles resolve only names and deleted collaborators keep their usage" do
    identities = [drivers(:one), operators(:one), ajudantes(:one), az_ajudantes(:one)]
    identities.each_with_index do |person, index|
      person.update_columns(nome: "Colaborador IA #{index}")
      record(user: nil, collaborator: person, feature: "variable_chat")
    end
    report = GeminiUsageReport.new(now: @now)
    assert_equal 4, report.summary[:active_users]
    assert_equal 4, report.users(query: "Colaborador IA")[:total]
    assert_equal identities.map(&:nome).sort, report.users[:rows].map { |row| row[:label] }.sort
    assert_equal 1, report.users(query: "Colaborador IA 2")[:total]
    identities.first.delete
    assert_equal 4, GeminiUsageReport.new(now: @now).summary[:accepted]
    assert GeminiUsageReport.new(now: @now).users[:rows].any? { |row| row[:label].include?("cadastro indisponível") }
  end

  private

  def record(user: users(:one), collaborator: nil, model: "gemini-3.6-flash", feature: "assistant", status: 200,
             at: @now - 10.seconds, input_tokens: 100, fingerprint: AiApiRequest.current_credential_fingerprint)
    AiApiRequest.create!(user: user, collaborator: collaborator, model: model, feature: feature, http_status: status, requested_at: at,
      input_tokens: status == 200 ? input_tokens : nil, output_tokens: status == 200 ? 20 : nil,
      duration_ms: 2000, credential_fingerprint: fingerprint)
  end
end
