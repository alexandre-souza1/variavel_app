module EmployeeSectorNavigation
  private

  def employee_sector_navigation(default_sector)
    allowed = current_user.employee_sectors
    sector = allowed.one? ? allowed.first : params[:employee_sector].presence_in(allowed) || default_sector
    params.slice(:q, :cargo, :turno, :status).permit(:q, :cargo, :turno, :status).to_h.symbolize_keys.merge(employee_sector: sector)
  end
end
