# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_10_03_145222) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_stat_statements"
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ajudantes", force: :cascade do |t|
    t.string "matricula"
    t.string "promax"
    t.string "nome"
    t.string "cpf"
    t.date "data_nascimento"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "autonomies", force: :cascade do |t|
    t.string "registration"
    t.string "equipment_type"
    t.string "service_type"
    t.string "plate"
    t.text "report"
    t.string "evidence"
    t.string "user_type"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "az_ajudantes", force: :cascade do |t|
    t.integer "matricula"
    t.string "nome"
    t.string "cpf"
    t.date "data_nascimento"
    t.integer "turno"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "az_mapas", force: :cascade do |t|
    t.date "data"
    t.integer "turno", default: [], array: true
    t.integer "tipo"
    t.float "resultado"
    t.boolean "atingiu_meta", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "budget_categories", force: :cascade do |t|
    t.string "name"
    t.string "sector"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "checklist_items", force: :cascade do |t|
    t.bigint "checklist_template_id", null: false
    t.string "description"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checklist_template_id"], name: "index_checklist_items_on_checklist_template_id"
  end

  create_table "checklist_responses", force: :cascade do |t|
    t.bigint "checklist_id", null: false
    t.bigint "checklist_item_id", null: false
    t.string "status"
    t.text "comment"
    t.string "photo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checklist_id"], name: "index_checklist_responses_on_checklist_id"
    t.index ["checklist_item_id"], name: "index_checklist_responses_on_checklist_item_id"
  end

  create_table "checklist_templates", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "plate_required"
    t.string "setor"
  end

  create_table "checklists", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "checklist_template_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "plate_id"
    t.index ["checklist_template_id"], name: "index_checklists_on_checklist_template_id"
    t.index ["plate_id"], name: "index_checklists_on_plate_id"
    t.index ["user_id"], name: "index_checklists_on_user_id"
  end

  create_table "cost_centers", force: :cascade do |t|
    t.string "name"
    t.string "sector"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "downloads", force: :cascade do |t|
    t.string "title"
    t.string "description"
    t.string "category"
    t.string "file_type"
    t.string "file_size"
    t.string "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sector"
  end

  create_table "drivers", force: :cascade do |t|
    t.string "matricula"
    t.string "promax"
    t.string "nome"
    t.string "cpf"
    t.date "data_nascimento"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "autonomy", default: false, null: false
  end

  create_table "fuel_consumptions", force: :cascade do |t|
    t.string "driver_name"
    t.decimal "km_per_liter"
    t.decimal "km_per_liter_goal"
    t.decimal "impact"
    t.decimal "total_value"
    t.integer "refuelings_count"
    t.decimal "liters"
    t.decimal "km_driven"
    t.decimal "co2_impact"
    t.string "period"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "invoice_numbers", force: :cascade do |t|
    t.string "number"
    t.bigint "invoice_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_invoice_numbers_on_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "supplier_id", null: false
    t.string "number"
    t.date "date"
    t.decimal "total"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "code"
    t.date "date_issued"
    t.date "due_date"
    t.integer "cost_center"
    t.text "document_urls", default: [], array: true
    t.bigint "purchaser_id"
    t.bigint "cost_center_id"
    t.bigint "budget_category_id"
    t.index ["budget_category_id"], name: "index_invoices_on_budget_category_id"
    t.index ["code"], name: "index_invoices_on_code", unique: true
    t.index ["cost_center_id"], name: "index_invoices_on_cost_center_id"
    t.index ["purchaser_id"], name: "index_invoices_on_purchaser_id"
    t.index ["supplier_id"], name: "index_invoices_on_supplier_id"
  end

  create_table "mapas", force: :cascade do |t|
    t.string "mapa"
    t.string "data"
    t.string "matric_motorista"
    t.float "fator"
    t.float "cx_total"
    t.float "cx_real"
    t.float "pdv_total"
    t.float "pdv_real"
    t.string "recarga"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "matric_ajudante"
    t.string "matric_ajudante_2"
  end

  create_table "operators", force: :cascade do |t|
    t.integer "matricula"
    t.string "nome"
    t.string "cpf"
    t.date "data_nascimento"
    t.integer "turno"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "autonomy", default: false, null: false
  end

  create_table "parametro_calculos", force: :cascade do |t|
    t.string "nome"
    t.float "valor"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "categoria"
  end

  create_table "plates", force: :cascade do |t|
    t.string "placa"
    t.string "setor"
    t.string "perfil"
    t.string "tipo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "remuneration_category_values", force: :cascade do |t|
    t.bigint "vehicle_remuneration_id", null: false
    t.bigint "budget_category_id", null: false
    t.decimal "value", precision: 15, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_category_id"], name: "index_remuneration_category_values_on_budget_category_id"
    t.index ["vehicle_remuneration_id", "budget_category_id"], name: "index_rcv_on_vehicle_and_budget", unique: true
    t.index ["vehicle_remuneration_id"], name: "index_remuneration_category_values_on_vehicle_remuneration_id"
  end

  create_table "remuneration_periods", force: :cascade do |t|
    t.string "label", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["label"], name: "index_remuneration_periods_on_label", unique: true
  end

  create_table "suppliers", force: :cascade do |t|
    t.string "name"
    t.string "cnpj"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "situation"
    t.string "email"
    t.string "phone"
    t.string "street"
    t.string "number"
    t.string "complement"
    t.string "neighborhood"
    t.string "city"
    t.string "state"
    t.string "zip_code"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role"
    t.string "name"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "vehicle_remunerations", force: :cascade do |t|
    t.bigint "remuneration_period_id", null: false
    t.string "vehicle_type", null: false
    t.integer "fleet_quantity", default: 0
    t.decimal "km_remunerated", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["remuneration_period_id", "vehicle_type"], name: "index_vr_on_period_and_vehicle", unique: true
    t.index ["remuneration_period_id"], name: "index_vehicle_remunerations_on_remuneration_period_id"
  end

  create_table "wms_tasks", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.string "task_type"
    t.string "plate"
    t.string "task_code"
    t.string "pallet"
    t.datetime "started_at"
    t.datetime "ended_at"
    t.integer "duration", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id"], name: "index_wms_tasks_on_operator_id"
    t.index ["started_at"], name: "index_wms_tasks_on_started_at"
    t.index ["task_code"], name: "index_wms_tasks_on_task_code"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "checklist_items", "checklist_templates"
  add_foreign_key "checklist_responses", "checklist_items"
  add_foreign_key "checklist_responses", "checklists"
  add_foreign_key "checklists", "checklist_templates"
  add_foreign_key "checklists", "plates"
  add_foreign_key "checklists", "users"
  add_foreign_key "invoice_numbers", "invoices"
  add_foreign_key "invoices", "budget_categories"
  add_foreign_key "invoices", "cost_centers"
  add_foreign_key "invoices", "suppliers"
  add_foreign_key "invoices", "users", column: "purchaser_id"
  add_foreign_key "remuneration_category_values", "budget_categories"
  add_foreign_key "remuneration_category_values", "vehicle_remunerations"
  add_foreign_key "vehicle_remunerations", "remuneration_periods"
  add_foreign_key "wms_tasks", "operators"
end
