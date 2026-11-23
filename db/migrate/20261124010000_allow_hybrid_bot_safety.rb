class AllowHybridBotSafety < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :agent_bots, name: 'agent_bot_safety_mode'
    add_check_constraint :agent_bots,
                         "safety_mode IS NULL OR safety_mode IN ('aws','aws_shadow','aws_custom','custom','hybrid','hybrid_shadow','dual')",
                         name: 'agent_bot_safety_mode'
  end

  def down
    if select_value("SELECT EXISTS (SELECT 1 FROM agent_bots WHERE safety_mode IN ('hybrid','hybrid_shadow','dual'))")
      raise ActiveRecord::IrreversibleMigration, 'Switch hybrid bots to a supported legacy mode before rollback'
    end

    remove_check_constraint :agent_bots, name: 'agent_bot_safety_mode'
    add_check_constraint :agent_bots, "safety_mode IS NULL OR safety_mode IN ('aws','aws_shadow','aws_custom','custom')",
                         name: 'agent_bot_safety_mode'
  end
end
