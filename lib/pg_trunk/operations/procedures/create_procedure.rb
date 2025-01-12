# frozen_string_literal: false

# @!parse
#   class ActiveRecord::Migration
#     # Create a procedure
#     #
#     # @param [#to_s] name (nil)
#     #   The qualified name of the procedure with arguments and returned value type
#     # @option [Boolean] :replace_existing (false) If the procedure should overwrite an existing one
#     # @option [#to_s] :language ("sql") The language (like "sql" or "plpgsql")
#     # @option [#to_s] :body (nil) The body of the procedure
#     # @option [Symbol] :security (:invoker) Define the role under which the procedure is invoked
#     #   Supported values: :invoker (default), :definer
#     # @option [#to_s] :comment The description of the procedure
#     # @yield [p] the block with the procedure's definition
#     # @yieldparam Object receiver of methods specifying the procedure
#     # @return [void]
#     #
#     # The syntax of the operation is the same as for `create_function`,
#     # but with only `security` option available. Notice, that
#     # procedures cannot return values so you're expected not to
#     # define a returned value as well.
#     #
#     # The procedure can be created either using inline syntax
#     #
#     # ```ruby
#     # create_procedure "metadata.set_foo(a int)",
#     #                  language: :sql,
#     #                  body: "SET foo = a",
#     #                  comment: "Sets foo value"
#     # ```
#     #
#     # or using a block:
#     #
#     # ```ruby
#     # create_procedure "metadata.set_foo(a int)" do |p|
#     #   p.language "sql" # (default)
#     #   p.body <<~SQL
#     #     SET foo = a
#     #   SQL
#     #   p.security :invoker # (default), also :definer
#     #   p.comment "Multiplies 2 integers"
#     # SQL
#     # ```
#     #
#     # With a `replace_existing: true` option,
#     # it will be created using the `CREATE OR REPLACE` clause.
#     # In this case the migration is irreversible because we
#     # don't know if and how to restore its previous definition.
#     #
#     # ```ruby
#     # create_procedure "set_foo(a int)",
#     #                  body: "SET foo = a",
#     #                  replace_existing: true
#     # ```
#     #
#     # A procedure without arguments is supported as well
#     #
#     # ```ruby
#     # # the same as "do_something()"
#     # create_procedure "do_something" do |p|
#     #   # ...
#     # end
#     # ```
#     def create_procedure(name, **options, &block); end
#   end
module PGTrunk::Operations::Procedures
  # @private
  class CreateProcedure < Base
    validates :body, presence: true
    validates :if_exists, :new_name, absence: true

    from_sql do |server_version|
      # Procedures were added to PostgreSQL in v11
      next if server_version < "11"

      <<~SQL.squish
        SELECT
          p.oid,
          (
            p.pronamespace::regnamespace || '.' || p.proname || '(' ||
            regexp_replace(
              regexp_replace(
                pg_get_function_arguments(p.oid), '^\s*IN\s+', '', 'g'
              ), '[,]\s*IN\s+', ',', 'g'
            ) || ')'
          ) AS name,
          p.prosrc AS body,
          l.lanname AS language,
          (
            CASE
              WHEN p.prosecdef THEN 'definer'
              ELSE 'invoker'
            END
          ) AS security,
          d.description AS comment
        FROM pg_proc p
          JOIN pg_trunk e ON e.oid = p.oid
          JOIN pg_language l ON l.oid = p.prolang
          LEFT JOIN pg_description d ON d.objoid = p.oid
        WHERE e.classid = 'pg_proc'::regclass
          AND p.prokind = 'p';
      SQL
    end

    def to_sql(version)
      # Procedures were added to PostgreSQL in v11
      check_version!(version)

      [create_proc, *comment_proc, register_proc].join(" ")
    end

    def invert
      irreversible!("replace_existing: true") if replace_existing
      DropProcedure.new(**to_h)
    end

    private

    def create_proc
      sql = "CREATE"
      sql << " OR REPLACE" if replace_existing
      sql << " PROCEDURE #{name.to_sql(true)}"
      sql << " LANGUAGE #{language&.downcase || 'sql'}"
      sql << " SECURITY DEFINER" if security == :definer
      sql << " AS $$#{body}$$;"
    end

    def comment_proc
      <<~SQL
        COMMENT ON PROCEDURE #{name.to_sql(true)}
        IS $comment$#{comment}$comment$;
      SQL
    end

    # Register the most recent `oid` of procedures with this schema/name
    # There can be several overloaded definitions, but we're interested
    # in that one we created just now so we can skip checking its args.
    def register_proc
      <<~SQL.squish
        WITH latest AS (
          SELECT
            oid,
            (proname = #{name.quoted} AND pronamespace = #{name.namespace}) AS ok
          FROM pg_proc
          WHERE prokind = 'p'
          ORDER BY oid DESC LIMIT 1
        )
        INSERT INTO pg_trunk (oid, classid)
          SELECT oid, 'pg_proc'::regclass
          FROM latest
          WHERE ok
        ON CONFLICT DO NOTHING;
      SQL
    end
  end
end
