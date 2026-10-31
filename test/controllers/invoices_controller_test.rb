require "test_helper"

class InvoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @supplier = Supplier.create!(name: "Fornecedor de teste", cnpj: SecureRandom.random_number(10**14).to_s, supplier_type: "other")
    @category = BudgetCategory.create!(name: "Manutenção #{SecureRandom.hex(4)}", sector: :frota)
    @cost_center = CostCenter.create!(name: "Centro #{SecureRandom.hex(4)}", sector: :frota)
  end

  test "form enables inline validation and required fields on initial and dynamic rows" do
    get new_invoice_path

    assert_response :success
    assert_select "form[data-controller='invoice-form'][data-turbo='false']"
    assert_select "input[name='invoice[date_issued]'][required]"
    assert_select ".nested-fields input[name$='[number]'][required]", count: 2
    assert_select "select[name='invoice[budget_category_id]'] option[data-sector='fleet']"
  end

  test "returns field errors without creating an invoice or uploading attachments" do
    attributes = valid_attributes.merge(code: "", supplier_id: "", documents: [upload])

    assert_no_difference ["Invoice.count", "ActiveStorage::Attachment.count"] do
      post invoices_path, params: { invoice: attributes }, as: :json
    end

    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("errors").key?("code")
    assert response.parsed_body.fetch("errors").key?("supplier_id")
  end

  test "nested errors use the dynamically submitted row key" do
    attributes = valid_attributes.merge(invoice_numbers_attributes: {
      "1760000000000" => { number: "", amount: "-1", cost_center_id: "" }
    })

    post invoices_path, params: { invoice: attributes }, as: :json

    assert_response :unprocessable_entity
    errors = response.parsed_body.fetch("invoice_number_errors").fetch("1760000000000")
    assert errors.key?("number")
    assert errors.key?("cost_center")
    assert errors.key?("amount")
  end

  test "duplicate code returns an inline error" do
    invoice = Invoice.create!(valid_attributes)

    assert_no_difference "Invoice.count" do
      post invoices_path, params: { invoice: valid_attributes.merge(code: invoice.code) }, as: :json
    end

    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("errors").key?("code")
  end

  test "JSON creation accepts multipart attachments and preserves the return destination" do
    assert_difference "Invoice.count" do
      post invoices_path, params: { invoice: valid_attributes.merge(documents: [upload]), document_types: ["boleto"],
                                   return_to: dashboard_invoices_path(year: 2026) },
                          headers: { "Accept" => "application/json" }
    end

    assert_response :created
    invoice = Invoice.find(response.parsed_body.fetch("id"))
    assert_equal invoice_path(invoice, return_to: dashboard_invoices_path(year: 2026)), response.parsed_body["redirect_url"]
    assert_equal 1, invoice.documents.count
    assert_equal "boleto", invoice.documents.first.blob.metadata["document_type"]
    assert_equal 1234.56.to_d, invoice.total
  end

  test "failed update keeps existing documents and identifies the submitted persisted row" do
    invoice = Invoice.create!(valid_attributes)
    invoice.documents.attach(upload)
    number = invoice.invoice_numbers.first

    patch invoice_path(invoice), params: { invoice: {
      invoice_numbers_attributes: { "87654321" => { id: number.id, number: "", amount: "-1" } },
      documents: [upload]
    } }, headers: { "Accept" => "application/json" }

    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("invoice_number_errors").fetch("87654321").key?("number")
    assert_equal 1, invoice.reload.documents.count
    assert_equal "123", number.reload.number
  end

  test "abastecimento can be saved without manually entering a code" do
    @category.update!(name: "Abastecimento")

    post invoices_path, params: { invoice: valid_attributes.merge(code: "") }, as: :json

    assert_response :created
    assert_match(/\AABAST-/, Invoice.find(response.parsed_body.fetch("id")).code)
  end

  test "successful update appends uploads and preserves existing attachments" do
    invoice = Invoice.create!(valid_attributes)
    invoice.documents.attach(upload)
    original_blob = invoice.documents.first.blob_id

    patch invoice_path(invoice), params: { invoice: { notes: "Atualizada", documents: [upload] }, document_types: ["boleto"] },
                                headers: { "Accept" => "application/json" }

    assert_response :success
    assert_equal invoice_path(invoice, return_to: invoices_path), response.parsed_body["redirect_url"]
    assert_equal 2, invoice.reload.documents.count
    assert_includes invoice.documents.pluck(:blob_id), original_blob
    assert_equal "boleto", invoice.documents.last.blob.metadata["document_type"]
  end

  test "removed rows do not receive errors or displace errors from newly added rows" do
    invoice = Invoice.create!(valid_attributes)
    number = invoice.invoice_numbers.first

    patch invoice_path(invoice), params: { invoice: { invoice_numbers_attributes: {
      "0" => { id: number.id, _destroy: "1" },
      "1760000000000" => { number: "", amount: "0,00", cost_center_id: @cost_center.id }
    } } }, as: :json

    assert_response :unprocessable_entity
    assert_equal ["1760000000000"], response.parsed_body.fetch("invoice_number_errors").keys
    assert_equal [number.id], invoice.reload.invoice_number_ids
  end

  private

  def valid_attributes
    { code: "NF-#{SecureRandom.hex(6)}", supplier_id: @supplier.id, purchaser_id: users(:one).id,
      budget_category_id: @category.id, date_issued: "2026-10-31", due_date: "2026-11-10",
      invoice_numbers_attributes: { "0" => { number: "123", amount: "1.234,56", cost_center_id: @cost_center.id } } }
  end

  def upload
    fixture_file_upload("pcd_routing.csv", "text/csv")
  end
end
