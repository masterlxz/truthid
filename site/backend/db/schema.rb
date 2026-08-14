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

ActiveRecord::Schema[8.1].define(version: 2026_08_14_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "customers", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_customers_on_email", unique: true
  end

  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_identities_on_customer_id"
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
  end

  add_foreign_key "identities", "customers"
end
