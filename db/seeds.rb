# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

ColorTheme.ensure_builtin_themes!

ColorTheme.find_or_create_by!(key: "halloween") do |theme|
  theme.assign_attributes(name: "Halloween", description: "Roxos, pêssego e dourado com abóboras e pequenos sustos.",
    base_color: "#522D60", primary_color: "#80426E", accent_color: "#F2A67B", highlight_color: "#FFD38B",
    decoration: "🎃", promotion_enabled: true, promotion_text: "Experimente o Halloween",
    promotion_starts_on: Date.new(2026, 10, 29), promotion_ends_on: Date.new(2026, 11, 3))
end

User.create!(
  name: "Usuário não registrado",
  email: "anon@system.local",
  password: SecureRandom.hex(10)
)
