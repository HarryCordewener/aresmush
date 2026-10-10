module AresMUSH
  module Pf2e

    # Who is running an encounter, and how far that lets it go.
    #
    #   event runner  any approved character. Runs an encounter with the creatures of the bestiaries
    #                 open to everyone (`pf2e.event_runner_bestiaries`), and cannot leave a character
    #                 Drained, Doomed or dead: what would kill leaves them unconscious.
    #   Plotmaster    whoever holds `kill_pc`. Any creature, one of their own making among them, and
    #                 their encounter may do all three. Nothing else of staff's comes with it.
    #   staff         as a Plotmaster, in any encounter.
    module Gm

      KINDS = [
        { 'name' => 'staff', 'is' => lambda { |char| char.is_admin? } },
        { 'name' => 'Plotmaster', 'is' => lambda { |char| char.has_permission?('kill_pc') } },
        { 'name' => 'event runner', 'is' => lambda { |_char| true } }
      ].freeze

      # What an event runner's encounter does not leave a character with.
      LASTING = %w{Drained Doomed}.freeze

      def self.kind(char)
        KINDS.find { |one| one['is'].call(char) }['name']
      end

      # Whether a character may do what only a Plotmaster or staff does.
      def self.plotmaster?(char)
        !char.nil? && kind(char) != 'event runner'
      end

      # Whether what happens in an encounter may kill a character, or leave them Drained or Doomed: its
      # GM's to say.
      def self.lethal?(encounter)
        !encounter.nil? && plotmaster?(PF2Encounter.gm_of(encounter))
      end

      # The encounter someone stands in, if what holds them is their state in one.
      def self.encounter_of(holder)
        holder.respond_to?(:encounter) ? holder.encounter : nil
      end

      def self.character?(holder)
        !Actors.of(holder).creature?
      end

      # Whether what happens to a character where they stand may kill them.
      def self.may_kill?(holder)
        lethal?(encounter_of(holder))
      end

      # Whether a condition passes a character by rather than landing: one of the lasting ones, coming
      # from someone else - `by` is their name - where the encounter may not leave them with it. What a
      # character does to themselves is theirs to choose.
      def self.spared?(holder, condition, by = nil)
        return false unless LASTING.include?(condition) && character?(holder)
        return false if by.to_s == holder.name

        !may_kill?(holder)
      end

      # ------------------------------------------------------------------------------
      # Creatures

      def self.open_bestiaries
        Array(Global.read_config('pf2e', 'event_runner_bestiaries'))
      end

      # Whether a creature of the bestiary is one this character may add.
      def self.open?(char, creature)
        plotmaster?(char) || open_bestiaries.include?((Bestiary.index[creature] || {})['pack'])
      end
    end
  end
end
