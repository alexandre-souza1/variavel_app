Warden::Manager.before_logout do |user, auth, _options|
  binding = auth.request.session[:mobile_push_binding]
  if user && binding.present?
    PushDevice.where(user_id: user.id, session_binding: binding).delete_all
    auth.request.session.delete(:mobile_push_binding)
  end
end
