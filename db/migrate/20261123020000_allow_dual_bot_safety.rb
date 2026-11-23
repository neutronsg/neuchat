class AllowDualBotSafety < ActiveRecord::Migration[7.0]
  def up
    remove_check_constraint :agent_bots, name: 'agent_bot_safety_mode'
    add_check_constraint :agent_bots, "safety_mode IS NULL OR safety_mode IN ('aws','aws_shadow','aws_custom','custom')",
                         name: 'agent_bot_safety_mode'
  end

  def down
    if select_value("SELECT EXISTS (SELECT 1 FROM agent_bots WHERE safety_mode = 'aws_custom')")
      raise ActiveRecord::IrreversibleMigration, 'Switch dual-protection bots to AWS before rollback'
    end

    remove_check_constraint :agent_bots, name: 'agent_bot_safety_mode'
    add_check_constraint :agent_bots, "safety_mode IS NULL OR safety_mode IN ('aws','aws_shadow','custom')", name: 'agent_bot_safety_mode'
  end
end
