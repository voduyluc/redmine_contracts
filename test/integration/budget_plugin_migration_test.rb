require 'test_helper'

class BudgetPluginMigrationTest < ActionController::IntegrationTest
  def setup
    configure_overhead_plugin
  end

  def load_test_fixture
    YAML.load(File.read(File.expand_path(File.dirname(__FILE__)) + "/../fixtures/budget_plugin_migration/budget.yml"))
  end

  context "migrate" do
    setup do
      @data = load_test_fixture
      @project_one = Project.generate!
      @project_two = Project.generate!
      # Stub out the Project finders because we need to match the ids but can't
      # be sure what ids object_daddy will give us
      Project.stubs(:find_by_id).with(1).returns(@project_one)
      Project.stubs(:find_by_id).with(2).returns(@project_one)

      @manager = User.generate!
      @role = Role.generate!
      User.add_to_project(@manager, @project_one, @role)
      User.add_to_project(@manager, @project_two, @role)

    end

    should "load a YAML dump of the old budget data" do
      RedmineContracts::BudgetPluginMigration.migrate(@data)

      assert_equal @data, RedmineContracts::BudgetPluginMigration.data
    end
    
    should "create a new Deliverable for each old Deliverable" do

      assert_difference("Deliverable.count", 3) do
        assert_difference("HourlyDeliverable.count", 2) do
          assert_difference("FixedDeliverable.count", 1) do
            RedmineContracts::BudgetPluginMigration.migrate(@data)
          end
        end
      end

    end
    
    should "create a new Contract for each project that had an old deliverable" do
      assert_difference("Contract.count", 2) do
        RedmineContracts::BudgetPluginMigration.migrate(@data)
      end

      assert_equal 1, @project_one.reload.contracts.first.deliverables.count
      assert_equal 2, @project_two.reload.contracts.first.deliverables.count
    end

    should "pick the first project member for the deliverable manager" do
      RedmineContracts::BudgetPluginMigration.migrate(@data)

      assert_equal [@manager, @manager, @manager], Deliverable.all.collect(&:manager)
    end

    should "create a new Overhead Budget record for any overhead" do
      assert_difference("OverheadBudget.count", 3) do
        RedmineContracts::BudgetPluginMigration.migrate(@data)
      end

      d = Deliverable.find_by_title("Deliverable One")
      assert_equal 1, d.overhead_budgets.count
      assert_equal 200, d.overhead_budget_total

      overhead = d.overhead_budgets.first
      assert overhead
      assert_equal 200, overhead.budget
      assert_equal 0, overhead.hours
    end

    should "create a new Overhead Budget record for any overhead percent" do
      assert_difference("OverheadBudget.count", 3) do
        RedmineContracts::BudgetPluginMigration.migrate(@data)
      end

      d = Deliverable.find_by_title("Deliverable 2")
      assert_equal 1, d.overhead_budgets.count
      assert_equal 12 * 25 * 1.5, d.overhead_budget_total # hourly

      overhead = d.overhead_budgets.first
      assert overhead
      assert_equal 450, overhead.budget
      assert_equal 0, overhead.hours

    end

    context "converting Fixed Deliverables" do
      should "convert fixed_cost to total" do
        RedmineContracts::BudgetPluginMigration.migrate(@data)

        d = FixedDeliverable.find_by_title("Version 1.0")
        assert_equal 30_000, d.total
      end
    end
  end
end

