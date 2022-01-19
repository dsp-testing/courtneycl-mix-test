# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hygeia.Repo.Migrations.VaccinationValidityCaseInfluence do
  @moduledoc false

  use Hygeia, :migration

  def change do
    execute(
      """
      CREATE
        VIEW case_phase_dates
        AS
          SELECT
            cases.uuid AS case_uuid,
            (phase->>'uuid')::uuid AS phase_uuid,
            LEAST(
              MIN(tests.tested_at),
              MIN(tests.laboratory_reported_at)
            ) AS first_test_date,
            GREATEST(
              MAX(tests.tested_at),
              MAX(tests.laboratory_reported_at)
            ) AS last_test_date,
            COALESCE(
              LEAST(
                MIN(tests.tested_at),
                MIN(tests.laboratory_reported_at),
                (cases.clinical->>'symptom_start')::date,
                (phase->>'start')::date
              ),
              (phase->>'order_date')::date,
              (phase->>'inserted_at')::date,
              cases.inserted_at
            ) AS case_first_known_date,
            COALESCE(
              GREATEST(
                MAX(tests.tested_at),
                MAX(tests.laboratory_reported_at),
                (cases.clinical->>'symptom_start')::date,
                (phase->>'end')::date
              ),
              (phase->>'order_date')::date,
              (phase->>'inserted_at')::date,
              cases.inserted_at
            ) AS case_last_known_date
            FROM cases
            CROSS JOIN
              UNNEST(cases.phases)
              AS phase
            LEFT JOIN
              tests
              ON
                tests.case_uuid = cases.uuid AND
                tests.result = 'positive'
            GROUP BY
              cases.uuid,
              phase
      """,
      """
        DROP
          VIEW case_phase_dates
      """
    )

    # janssen: min one vaccination, waiting period of 22 days, valid 1 year
    janssen_query = """
    SELECT
      vaccination_shots.person_uuid AS person_uuid,
      vaccination_shots.uuid AS vaccination_shot_uuid,
      DATERANGE(
        (vaccination_shots.date + INTERVAL '22 day')::date,
        (vaccination_shots.date + INTERVAL '1 year 22 day')::date
      ) AS range
      FROM vaccination_shots
      WHERE vaccination_shots.vaccine_type = 'janssen'
    """

    # 'moderna', 'pfizer', 'astra_zeneca':
    # valid if more than two combined, no waiting period, valid 1 year
    moderna_pfizer_astra_combo_query = """
    SELECT
      result.person_uuid,
      result.vaccination_shot_uuid,
      result.range
      FROM (
        SELECT
        vaccination_shots.person_uuid AS person_uuid,
          vaccination_shots.uuid AS vaccination_shot_uuid,
          CASE
            -- More than 2 vaccinations, shot is valid
            WHEN (
              ROW_NUMBER() OVER (
                PARTITION BY vaccination_shots.person_uuid
                ORDER BY vaccination_shots.date
              ) >= 2
            ) THEN
              DATERANGE(
                vaccination_shots.date,
                (vaccination_shots.date + INTERVAL '1 year')::date
              )
            ELSE NULL
          END AS range
          FROM vaccination_shots
          WHERE vaccination_shots.vaccine_type IN ('pfizer', 'moderna', 'astra_zeneca')
      ) AS result
      WHERE result.range IS NOT NULL
    """

    # 'astra_zeneca', 'pfizer', 'moderna', 'sinopharm', 'sinovac' 'covaxin':
    # min two, no waiting period, valid 1 year
    double_query = """
    SELECT
      result.person_uuid,
      result.vaccination_shot_uuid,
      result.range
      FROM (
        SELECT
        vaccination_shots.person_uuid AS person_uuid,
          vaccination_shots.uuid AS vaccination_shot_uuid,
          CASE
            -- More than 2 vaccinations, shot is valid
            WHEN (
              ROW_NUMBER() OVER (
                PARTITION BY vaccination_shots.person_uuid, vaccination_shots.vaccine_type
                ORDER BY vaccination_shots.date
              ) >= 2
            ) THEN
              DATERANGE(
                vaccination_shots.date,
                (vaccination_shots.date + INTERVAL '1 year')::date
              )
            ELSE NULL
          END AS range
          FROM vaccination_shots
          WHERE vaccination_shots.vaccine_type IN ('astra_zeneca', 'pfizer', 'moderna', 'sinopharm', 'sinovac', 'covaxin')
      ) AS result
      WHERE result.range IS NOT NULL
    """

    # 'astra_zeneca', 'pfizer', 'moderna', 'sinopharm', 'sinovac', 'covaxin':
    # externally convalescent, no waiting period, valid 1 year
    externally_convalescent_query = """
    SELECT
      result.person_uuid,
      result.vaccination_shot_uuid,
      result.range
      FROM (
        SELECT
          vaccination_shots.person_uuid AS person_uuid,
          vaccination_shots.uuid AS vaccination_shot_uuid,
          CASE
            WHEN (
              ROW_NUMBER() OVER (
                PARTITION BY vaccination_shots.person_uuid, vaccination_shots.vaccine_type
                ORDER BY vaccination_shots.date
              ) = 1
            ) THEN
              DATERANGE(
                vaccination_shots.date,
                (vaccination_shots.date + INTERVAL '1 year')::date
              )
            ELSE NULL
          END AS range
          FROM people
          JOIN
            vaccination_shots
            ON vaccination_shots.person_uuid = people.uuid
          WHERE
            people.convalescent_externally AND
            vaccination_shots.vaccine_type IN ('astra_zeneca', 'pfizer', 'moderna', 'sinopharm', 'sinovac', 'covaxin')
      ) AS result
      WHERE result.range IS NOT NULL
    """

    # 'astra_zeneca', 'pfizer', 'moderna', 'sinopharm', 'sinovac', 'covaxin':
    # internally convalescent, no waiting period, valid 1 year
    internally_convalescent_query = """
    SELECT
      result.person_uuid,
      result.vaccination_shot_uuid,
      result.range
      FROM (
        SELECT
          people.uuid AS person_uuid,
          vaccination_shots.uuid AS vaccination_shot_uuid,
          CASE
            -- case is more than 4 weeks old, first shot is valid
            WHEN (
              ROW_NUMBER() OVER (
                PARTITION BY vaccination_shots.person_uuid, vaccination_shots.vaccine_type
                ORDER BY vaccination_shots.date
              ) = 1 AND
              DATERANGE(
                (COALESCE(case_phase_dates.first_test_date, case_phase_dates.case_first_known_date) - INTERVAL '4 week')::date,
                (case_phase_dates.case_last_known_date + INTERVAL '4 week')::date
              ) <<
              DATERANGE(
                vaccination_shots.date,
                (vaccination_shots.date + INTERVAL '1 year')::date
              )
            ) THEN
              DATERANGE(
                vaccination_shots.date,
                (vaccination_shots.date + INTERVAL '1 year')::date
              )
            -- case is after shot validity, shot is not valid
            WHEN (
              ROW_NUMBER() OVER (
                PARTITION BY vaccination_shots.person_uuid, vaccination_shots.vaccine_type
                ORDER BY vaccination_shots.date
              ) = 1 AND
              DATERANGE(
                (COALESCE(case_phase_dates.first_test_date, case_phase_dates.case_first_known_date) - INTERVAL '4 week')::date,
                (case_phase_dates.case_last_known_date + INTERVAL '4 week')::date
              ) >>
              DATERANGE(
                vaccination_shots.date,
                (vaccination_shots.date + INTERVAL '1 year')::date
              )
            ) THEN
              NULL
            -- case is inside shot validity, shot is valid after case + 4 weeks
            WHEN (
              ROW_NUMBER() OVER (
                PARTITION BY vaccination_shots.person_uuid, vaccination_shots.vaccine_type
                ORDER BY vaccination_shots.date
              ) = 1 AND
              DATERANGE(
                (COALESCE(case_phase_dates.first_test_date, case_phase_dates.case_first_known_date) - INTERVAL '4 week')::date,
                (case_phase_dates.case_last_known_date + INTERVAL '4 week')::date
              ) &&
              DATERANGE(
                vaccination_shots.date,
                (vaccination_shots.date + INTERVAL '1 year')::date
              )
            ) THEN
              DATERANGE(
                (case_phase_dates.case_last_known_date + INTERVAL '4 week')::date,
                (vaccination_shots.date + INTERVAL '1 year')::date
              )
          END AS range
          FROM people
          JOIN
            vaccination_shots
            ON vaccination_shots.person_uuid = people.uuid
          JOIN
            cases
            ON cases.person_uuid = people.uuid
          JOIN
            UNNEST(cases.phases)
            AS index_phases
            ON index_phases->'details'->>'__type__' = 'index'
          JOIN
            case_phase_dates
            ON
              case_phase_dates.case_uuid = cases.uuid AND
              case_phase_dates.phase_uuid = (index_phases->>'uuid')::uuid
          WHERE vaccination_shots.vaccine_type IN ('astra_zeneca', 'pfizer', 'moderna', 'sinopharm', 'sinovac', 'covaxin')
      ) AS result
      WHERE result.range IS NOT NULL
    """

    execute(
      """
      CREATE OR REPLACE
        VIEW vaccination_shot_validity
        AS
          #{janssen_query}
          UNION
          #{moderna_pfizer_astra_combo_query}
          UNION
          #{double_query}
          UNION
          #{externally_convalescent_query}
          UNION
          #{internally_convalescent_query}
      """,
      """
      CREATE
        OR REPLACE
        VIEW vaccination_shot_validity
        AS
          SELECT
            result.person_uuid,
            result.vaccination_shot_uuid,
            result.range
            FROM (
              SELECT
                people.uuid AS person_uuid,
                vaccination_shots.uuid AS vaccination_shot_uuid,
                CASE
                  WHEN (
                    ROW_NUMBER() OVER (
                      PARTITION BY people.uuid
                      ORDER BY vaccination_shots.date
                    ) >= 2 OR
                    people.convalescent_externally OR
                    COALESCE(
                      (index_phases->>'order_date')::date,
                      (index_phases->>'inserted_at')::date,
                      cases.inserted_at::date
                    ) >= vaccination_shots.date
                  ) THEN
                    DATERANGE(
                      vaccination_shots.date,
                      (vaccination_shots.date + INTERVAL '1 year')::date
                    )
                  ELSE NULL
                END AS range
                FROM people
                JOIN
                  vaccination_shots
                  ON vaccination_shots.person_uuid = people.uuid
                LEFT JOIN
                  cases
                  ON cases.person_uuid = people.uuid
                LEFT JOIN
                  UNNEST(cases.phases)
                  AS index_phases
                  ON index_phases->'details'->>'__type__' = 'index'
                WHERE
                  vaccination_shots.vaccine_type IN ('pfizer', 'moderna')
            ) AS result
            WHERE result.range IS NOT NULL
          UNION
          SELECT
            people.uuid AS person_uuid,
            vaccination_shots.uuid,
            DATERANGE(
              (vaccination_shots.date + INTERVAL '22 day')::date,
              (vaccination_shots.date + INTERVAL '1 year 22 day')::date
            ) AS range
          FROM people
          JOIN
            vaccination_shots
            ON vaccination_shots.person_uuid = people.uuid
          WHERE
            vaccination_shots.vaccine_type = 'janssen';
      """
    )
  end
end
