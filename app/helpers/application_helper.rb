module ApplicationHelper
  def label_text_color(color)
    hex = color.to_s.delete_prefix("#")
    hex = hex.chars.map { |character| character * 2 }.join if hex.match?(/\A[0-9a-f]{3}\z/i)
    return "#ffffff" unless hex.match?(/\A[0-9a-f]{6}\z/i)

    channels = hex.scan(/../).map do |channel|
      value = channel.to_i(16) / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    luminance = channels.zip([0.2126, 0.7152, 0.0722]).sum { |channel, weight| channel * weight }
    white_contrast = 1.05 / (luminance + 0.05)
    black_contrast = (luminance + 0.05) / 0.05
    white_contrast >= black_contrast ? "#ffffff" : "#000000"
  end

  def disclosure_arrow(css_class: nil, **attributes)
    tag.i(**attributes, class: class_names("bi", "bi-arrow-right", "app-disclosure-arrow", css_class), aria: { hidden: true })
  end

  # Retorna um hash com os registros paginados e informações de paginação
  def paginate_records(relation, params, per_page: 15)
    current_page = (params[:page] || 1).to_i
    total_pages = (relation.count / per_page.to_f).ceil

    records = relation.offset((current_page - 1) * per_page).limit(per_page)

    {
      records: records,
      current_page: current_page,
      total_pages: total_pages,
      per_page: per_page
    }
  end

  def category_color(budget_category)
    # Mapeia cores baseadas no setor ou nome da categoria
    colors = {
      'combustivel' => 'warning',
      'manutencao' => 'info',
      'pecas' => 'success',
      'seguro' => 'danger',
      'outros' => 'secondary'
    }

    # Tenta pelo setor primeiro, depois pelo nome
    color_key = budget_category.sector.downcase
    colors[color_key] || 'primary'
  end

  def category_icon(budget_category)
    # Mapeia ícones baseados no setor ou nome da categoria
    icons = {
      'combustivel' => 'gas-pump',
      'manutencao' => 'tools',
      'pecas' => 'cog',
      'seguro' => 'shield-alt',
      'outros' => 'tag'
    }

    # Tenta pelo setor primeiro, depois pelo nome
    icon_key = budget_category.sector.downcase
    icons[icon_key] || 'tag'
  end

  def field_with_errors(form, field, &block)
    content_tag(:div, class: "mb-3") do
      concat capture(&block)
      if form.object.errors[field].any?
        concat content_tag(:div, form.object.errors[field].first, class: "text-danger mt-1")
      end
    end
  end

  def user_avatar(user, size = 40)

    return content_tag(:div,
      '<i class="bi bi-person-fill text-secondary"></i>'.html_safe,
      class: "d-flex align-items-center justify-content-center rounded-circle shadow-sm border border-2 border-white bg-light",
      style: "width: #{size}px; height: #{size}px;"
    ) unless user.photo.attached?


    if user.photo.blob.service_name == "cloudinary"

      cl_image_tag(
        user.photo.key,
        width: size,
        height: size,
        crop: :fill,
        gravity: :face,
        class: "rounded-circle shadow-sm border border-2 border-white",
        alt: "Avatar"
      )

    else

      image_tag(
        user.photo.variant(resize_to_limit: [size, size]),
        class: "rounded-circle shadow-sm border border-2 border-white",
        alt: "Avatar"
      )

    end
  end
end
