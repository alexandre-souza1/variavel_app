namespace :employees do
  desc 'List reconciliation issues for DU/AZ collaborators without changing any data'
  task audit: :environment do
    puts JSON.pretty_generate(Employees::Audit.call)
  end
end
