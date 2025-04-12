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

ActiveRecord::Schema[7.1].define(version: 2025_04_12_192935) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
  end

end
