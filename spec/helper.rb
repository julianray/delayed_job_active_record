require "simplecov"
require "coveralls"

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
])

SimpleCov.start do
  add_filter "/spec/"
  minimum_coverage(73.33)
end

require "logger"
require "rspec"

begin
  require "protected_attributes"
rescue LoadError # rubocop:disable HandleExceptions
end
require "delayed_job_active_record"
require "delayed/backend/shared_spec"

Delayed::Worker.logger = Logger.new("/tmp/dj.log")
ENV["RAILS_ENV"] = "test"

db_adapter, gemfile = ENV["ADAPTER"], ENV["BUNDLE_GEMFILE"]
db_adapter ||= gemfile && gemfile[%r{gemfiles/(.*?)/}] && $1 # rubocop:disable PerlBackrefs
db_adapter ||= "sqlite3"

config = YAML.load(File.read("spec/database.yml"))
ActiveRecord::Base.establish_connection config[db_adapter]
ActiveRecord::Base.logger = Delayed::Worker.logger
ActiveRecord::Migration.verbose = false

migration_template = File.open('generators/delayed_job/templates/migration')

# need to eval the template with the migration_version intact
template_context = Object.new
template_context.instance_eval <<-EVAL
  private def migration_version
    if Rails::VERSION::MAJOR >= 5
      "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
    end
  end
EVAL

migration_ruby = ERB.new(migration_template.read).result(template_context)
eval(migration_ruby)

ActiveRecord::Schema.define do
  CreateDelayedJobs.up

  create_table :stories, primary_key: :story_id, force: true do |table|
    table.string :text
    table.boolean :scoped, default: true
  end
end

# Purely useful for test cases...
class Story < ActiveRecord::Base
  if ::ActiveRecord::VERSION::MAJOR < 4 && ActiveRecord::VERSION::MINOR < 2
    set_primary_key :story_id
  else
    self.primary_key = :story_id
  end
  def tell
    text
  end

  def whatever(n, _)
    tell * n
  end
  default_scope { where(scoped: true) }

  handle_asynchronously :whatever
end

# Add this directory so the ActiveSupport autoloading works
ActiveSupport::Dependencies.autoload_paths << File.dirname(__FILE__)
