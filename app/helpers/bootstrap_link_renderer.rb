class BootstrapLinkRenderer < Kaminari::Helpers::Tag
  def to_s
    if @page.current?
      tag.li(tag.span(@page, class: 'page-link'), class: 'page-item active')
    else
      tag.li(tag.a(@page, href: @url, class: 'page-link'), class: 'page-item')
    end
  end
end
