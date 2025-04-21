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

ActiveRecord::Schema[7.1].define(version: 2025_04_21_121810) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "ajudantes", force: :cascade do |t|
    t.string "matricula"
    t.string "promax"
    t.string "nome"
    t.string "cpf"
    t.date "data_nascimento"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "drivers", force: :cascade do |t|
    t.string "matricula"
    t.string "promax"
    t.string "nome"
    t.string "cpf"
    t.date "data_nascimento"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "mapas", force: :cascade do |t|
    t.string "mapa"
    t.string "data"
    t.string "matric_motorista"
    t.float "fator"
    t.integer "cx_total"
    t.integer "cx_real"
    t.integer "pdv_total"
    t.integer "pdv_real"
    t.string "recarga"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "matric_ajudante"
  end

  create_table "parametro_calculos", force: :cascade do |t|
    t.string "nome"
    t.decimal "valor"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "categoria"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

end
