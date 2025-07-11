# app/helpers/bootstrap_pagination_renderer.rb
module BootstrapPaginationRenderer
  class LinkRenderer < WillPaginate::ActionView::LinkRenderer
    protected

    def html_container(html)
      tag(:nav, tag(:ul, html, class: 'pagination pagination-sm justify-content-center'))
    end

    def page_number(page)
      if page == current_page
        tag(:li, tag(:span, page, class: 'page-link'), class: 'page-item active')
      else
        tag(:li, link(page, page, class: 'page-link'), class: 'page-item')
      end
    end

    def gap
      tag(:li, tag(:span, '&hellip;', class: 'page-link'), class: 'page-item disabled')
    end

    def previous_or_next_page(page, text, classname)
      if page
        tag(:li, link(text, page, class: 'page-link'), class: "page-item #{classname}")
      else
        tag(:li, tag(:span, text, class: 'page-link'), class: "page-item disabled #{classname}")
      end
    end
  end
end
