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

ActiveRecord::Schema[7.1].define(version: 2025_07_28_161124) do
  # These are extensions that must be enabled in order to support this database
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

  create_table "az_coletivas", force: :cascade do |t|
    t.date "data"
    t.integer "tipo"
    t.string "turno"
    t.float "resultado"
    t.boolean "atingiu_meta", default: false
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

  create_table "az_operadors", force: :cascade do |t|
    t.string "matricula"
    t.string "nome"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "az_periodos", force: :cascade do |t|
    t.date "inicio"
    t.date "fim"
    t.string "descricao"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "az_tarefa_wms", force: :cascade do |t|
    t.bigint "az_operador_id", null: false
    t.date "data"
    t.integer "quantidade"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["az_operador_id"], name: "index_az_tarefa_wms_on_az_operador_id"
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

  create_table "meta", force: :cascade do |t|
    t.integer "tipo", null: false
    t.decimal "valor", null: false
    t.date "data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tipo", "data"], name: "index_meta_on_tipo_and_data", unique: true
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
  add_foreign_key "az_tarefa_wms", "az_operadors"
  add_foreign_key "checklist_items", "checklist_templates"
  add_foreign_key "checklist_responses", "checklist_items"
  add_foreign_key "checklist_responses", "checklists"
  add_foreign_key "checklists", "checklist_templates"
  add_foreign_key "checklists", "plates"
  add_foreign_key "checklists", "users"
  add_foreign_key "wms_tasks", "operators"
end
