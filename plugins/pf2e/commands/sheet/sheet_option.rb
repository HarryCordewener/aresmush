module AresMUSH
  module Pf2e

    # `sheet/option` - the circumstances a character's own gear and feats offer, and which are on.
    class PF2RollOptionCmd
      include CommandHandler

      attr_accessor :option, :setting

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.option = downcase_arg(args.arg1)
        self.setting = downcase_arg(args.arg2)
      end

      # Whose options these are: the enactor's own. `+e/option` names a combatant instead.
      def holder
        enactor
      end

      # Who the list is headed for, where that is not whoever reads it.
      def listed_for
        nil
      end

      def handle
        return client.emit PF2RollOptionsTemplate.new(Pf2e::RollOptions.declared(holder), listed_for).render if
          self.option.blank?

        found = Pf2e::RollOptions.find(holder, self.option)

        if !found
          client.emit_failure t('pf2e.no_such_option', :option => self.option)
          return
        end

        change(found)
      end

      # Naming an option with nothing after it turns it off or on, whichever it is not, because that is
      # what a switch does. `=default` hands it back to whatever declared it.
      def change(found)
        name = found['option']

        if self.setting == 'default'
          Pf2e::RollOptions.clear(holder, name)
          return client.emit_success t('pf2e.option_default', :option => name)
        end

        choice = Array(found['choices']).find { |one| one['value'].casecmp?(self.setting.to_s) }

        if choice
          Pf2e::RollOptions.set(holder, name, choice['value'])
          return client.emit_success t('pf2e.option_set_to', :option => name, :value => choice['value'])
        end

        if !self.setting.blank? && found['choices'].to_a.any? && !%w{on yes off no}.include?(self.setting)
          return client.emit_failure t('pf2e.no_such_choice_for_option', :option => name,
                                       :choices => found['choices'].map { |one| one['value'] }.join(', '))
        end

        on = case self.setting
             when 'on', 'yes' then true
             when 'off', 'no' then false
             else !found['on']
             end

        Pf2e::RollOptions.set(holder, name, on)

        client.emit_success t(on ? 'pf2e.option_on' : 'pf2e.option_off', :option => name)
      end
    end


    # `+e/option <combatant>=<option>[/<on|off|default|choice>]` - a circumstance a combatant's own rules
    # declare, switched by the GM: Air Scamp heals only in open air, and the GM is who knows whether it
    # is. With no option named, the combatant's options and which are on.
    #
    # `sheet/option` for a character's own; this for anyone in the encounter, so it is the GM's. It lives
    # beside `sheet/option` because it is that command pointed elsewhere, and a subclass has to be read
    # after its parent - the encounter commands are loaded before the sheet's.
    class PF2EncounterOptionCmd < PF2RollOptionCmd

      attr_accessor :who

      def parse_args
        who, _, rest = cmd.args.to_s.partition('=')
        option, _, setting = rest.partition('/')

        self.who = who.strip
        self.option = option.strip.downcase
        self.setting = setting.strip.downcase
      end

      def required_args
        [ self.who ]
      end

      def holder
        @combatant&.holder
      end

      def listed_for
        @combatant.ref
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        found = Combatants.find(encounter, self.who)

        return if CharState.emit_error!(client, found)

        @combatant = found.state

        super
      end
    end
  end
end
