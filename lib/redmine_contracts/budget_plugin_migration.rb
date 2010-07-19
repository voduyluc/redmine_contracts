require 'pp'

module RedmineContracts
  class BudgetPluginInstalledError < StandardError; end
  
  # TODO: decide how this is activated.
  # Have the user dump yaml themselves?  Or rename the tables and
  # SQL select the data out into yaml?
  # Deliverable.all.collect {|d| d.attributes}.to_yaml
  class BudgetPluginMigration
    @@data = nil

    def self.check_for_installed_budget_plugin
      if Redmine::Plugin.registered_plugins.keys.include?(:budget_plugin)
        raise BudgetPluginInstalledError, "The budget plugin is still installed. Please remove it and retry the conversion"
      end
    end

    def self.rename_old_tables
      ActiveRecord::Migration.rename_table(:deliverables, :budget_plugin_deliverables)
    end

    def self.export_data

    end

    def self.migrate_contracts
      ::Engines.plugins['redmine_contracts'].migrate
    end
    
    def self.migrate(old_data)
      @@data = old_data

      ActiveRecord::Base.transaction do
        @@data.each do |old_deliverable|

          deliverable = Deliverable.new(
                                        :title => old_deliverable['subject'],
                                        :end_date => old_deliverable['due'],
                                        :notes => old_deliverable['description']
                                        )
          deliverable.type = old_deliverable['type']
          project = Project.find(old_deliverable['project_id'])
          contract = Contract.find_by_project_id(project.id)
          contract ||= create_new_contract(old_deliverable)

          deliverable.contract = contract
          deliverable.manager = project.users.first          

          case old_deliverable['type']
          when 'FixedDeliverable'
            @total = deliverable.total = old_deliverable['fixed_cost']
          when 'HourlyDeliverable'
            @total = old_deliverable['total_hours'].to_f * old_deliverable['cost_per_hour'].to_f

            if old_deliverable['total_hours'].present? || old_deliverable['cost_per_hour'].present?
              deliverable.labor_budgets << LaborBudget.new(:deliverable => deliverable,
                                                           :budget => @total,
                                                           :hours => old_deliverable['total_hours'])
            end
          else
            @total = 0
          end

          convert_overhead(deliverable, old_deliverable, @total)
          convert_materials(deliverable, old_deliverable, @total)
          append_old_deliverable_to_notes(old_deliverable, deliverable)
          
          deliverable.save!
        end
      end
    end

    def self.data
      @@data
    end

    private

    def self.create_new_contract(old_deliverable)
      project = Project.find(old_deliverable['project_id'])

      contract = Contract.new(:name => 'Converted Contract',
                              :start_date => old_deliverable['due'],
                              :end_date => old_deliverable['due']) do |c|
        c.project = project
        c.account_executive = project.users.first
      end

      contract.save!
      contract
    end

    def self.convert_overhead(deliverable, old_deliverable, total)
      if old_deliverable['overhead'].present?
        deliverable.overhead_budgets << OverheadBudget.new(:deliverable => deliverable,
                                                           :budget => old_deliverable['overhead'],
                                                           :hours => 0)
      elsif old_deliverable['overhead_percent'].present?
        overhead = total * (old_deliverable['overhead_percent'].to_f / 100)
        deliverable.overhead_budgets << OverheadBudget.new(:deliverable => deliverable,
                                                           :budget => overhead,
                                                           :hours => 0)

      end
    end
    
    def self.convert_materials(deliverable, old_deliverable, total)
      if old_deliverable['materials'].present? && old_deliverable['materials'] > 0.0
        deliverable.overhead_budgets << OverheadBudget.new(:deliverable => deliverable,
                                                           :budget => old_deliverable['materials'],
                                                           :hours => 0)

      elsif old_deliverable['materials_percent'].present? && old_deliverable['materials_percent'] > 0.0
        materials = total * (old_deliverable['materials_percent'].to_f / 100)
        deliverable.overhead_budgets << OverheadBudget.new(:deliverable => deliverable,
                                                           :budget => materials,
                                                           :hours => 0)

      end
    end

    def self.append_old_deliverable_to_notes(old_deliverable, new_deliverable)
      new_deliverable.notes += "Converted data:\n<pre>" + old_deliverable.pretty_inspect + "</pre>"
    end
  end
end