module RoutineActivitiesHelper
  def routine_activity_value(activity, value)
    return "Vazio" if value.nil?

    routine_value_display(
      activity.routine_value.routine_indicator,
      value
    )
  end

  def routine_activity_user_name(user)
    return user.name if user.respond_to?(:name) && user.name.present?

    return user.full_name if user.respond_to?(:full_name) &&
                             user.full_name.present?

    return user.email if user.respond_to?(:email) &&
                         user.email.present?

    "Usuário ##{user.id}"
  end

  def routine_activity_date_label(date)
    return "Hoje" if date == Date.current
    return "Ontem" if date == Date.current - 1.day

    l(date, format: :long)
  end
end
