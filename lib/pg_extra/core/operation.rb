# frozen_string_literal: false

require_relative "operation/callbacks"
require_relative "operation/attributes"
require_relative "operation/generators"

module PGExtra
  # @api private
  # Base class for operations.
  # Inherit this class to define new operation.
  class Operation
    include Callbacks
    include Attributes
    include Generators

    attribute :comment, :string, desc: \
              "The comment to the object"
    attribute :force, :pg_extra_symbol, desc: \
              "How to process dependent objects"
    attribute :if_exists, :boolean, desc: \
              "Don't fail if the object is absent"
    attribute :if_not_exists, :boolean, desc: \
              "Don't fail if the object is already present"
    attribute :name, :pg_extra_qualified_name, desc: \
              "The qualified name of the object"
    attribute :new_name, :pg_extra_qualified_name, aliases: :to, desc: \
              "The new name of the object to rename to"
    attribute :oid, :integer, desc: \
              "The oid of the database object"
    attribute :version, :integer, aliases: :revert_to_version, desc: \
              "The version of the SQL snippet"

    private

    # Helper to read a versioned snippet for a specific
    # kind of objects
    def read_snippet_from(kind)
      return if kind.blank? || name.blank? || version.blank?

      filename = format(
        "db/%<kind>s/%<name>s_v%<version>02d.sql",
        kind: kind.to_s.pluralize,
        name: name.routine,
        version: version,
      )
      filepath = Rails.root.join(filename)
      File.read(filepath).sub(/;\s*$/, "")
    end
  end
end
