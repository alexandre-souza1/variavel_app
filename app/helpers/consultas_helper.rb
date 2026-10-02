module ConsultasHelper
  def personal_schedule_status_code(status)
    { 'working' => 'T', 'off' => 'F', 'dsr' => 'D', 'unavailable' => 'I', 'vacation' => 'V', 'pending' => '?' }.fetch(status, '—')
  end
end
