# frozen_string_literal: true

module PGExtra
  # @private
  # The module adds custom type casting
  module CustomTypes
    # All custom types are typecasted to strings in Rails
    TYPE = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::SpecializedString

    def self.known
      @known ||= Set.new([])
    end

    def enable_pg_extra_types
      execute(<<~SQL).each { |item| enable_pg_extra_type item["name"] }
        SELECT (
          CASE
          WHEN t.typnamespace = 'public'::regnamespace THEN t.typname
          ELSE t.typnamespace::regnamespace || '.' || t.typname
          END
        ) AS name
        FROM pg_extra e JOIN pg_type t ON t.oid = e.oid
        WHERE e.classid = 'pg_type'::regclass
      SQL
    end

    def enable_pg_extra_type(type)
      type = type.to_s
      CustomTypes.known << type
      type_map.register_type(type, TYPE.new(type)) unless type_map.key?(type)
    end

    def valid_type?(type)
      CustomTypes.known.include?(type.to_s) || super
    end
  end
end
