module MeetingMinutesHelper
  def meeting_status_classes(meeting)
    [
      "meeting-minute-status",
      format("meeting-minute-status--%s", meeting.status)
    ].join(" ")
  end
end
