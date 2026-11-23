-- Phase 4 workload based on queries/workload_30.sql.
-- We kept the query markers so the benchmark script can still find each query.
-- Write queries run inside a transaction and are rolled back at the end.
SET search_path TO linkedin;
BEGIN;

-- Reads: profile and network
-- @R01
-- Profile header: member 1023 with their current position and company
SELECT m.member_id, m.first_name, m.last_name, m.headline, p.title, c.company_name
FROM members m
LEFT JOIN positions p ON p.member_id = m.member_id AND p.end_date IS NULL
LEFT JOIN companies c ON c.company_id = p.company_id
WHERE m.member_id = 1023;

-- @R02
-- Experience section: member 1023's positions, latest first
SELECT p.title, c.company_name, p.employment_type, p.start_date, p.end_date
FROM positions p
JOIN companies c ON c.company_id = p.company_id
WHERE p.member_id = 1023
ORDER BY p.start_date DESC;

-- @R03
-- "My Network": everyone connected to member 1023
-- Check each endpoint separately so both lookups can use an index.
SELECT connection_id, connected_at
FROM (
    SELECT member_b AS connection_id, connected_at FROM connections WHERE member_a = 1023
    UNION ALL
    SELECT member_a AS connection_id, connected_at FROM connections WHERE member_b = 1023
) edges
ORDER BY connected_at DESC;

-- @R04
-- Profile page: mutual connections of member 1023 and member 356
-- Build each person's connections with one lookup per endpoint, then match friends.
WITH x AS (
    SELECT member_b AS friend FROM connections WHERE member_a = 1023
    UNION ALL
    SELECT member_a AS friend FROM connections WHERE member_b = 1023
), y AS (
    SELECT member_b AS friend FROM connections WHERE member_a = 356
    UNION ALL
    SELECT member_a AS friend FROM connections WHERE member_b = 356
)
SELECT x.friend FROM x JOIN y USING (friend);

-- @R05
-- "People you may know": 2nd-degree connections of member 1023 ranked by mutual connections
-- Follow each connection in turn and leave out people already in the network.
WITH my_conn AS (
    SELECT member_b AS f FROM connections WHERE member_a = 1023
    UNION ALL
    SELECT member_a AS f FROM connections WHERE member_b = 1023
), second_edges AS (
    SELECT mc.f, c.member_b AS suggestion
    FROM my_conn mc JOIN connections c ON c.member_a = mc.f
    UNION ALL
    SELECT mc.f, c.member_a AS suggestion
    FROM my_conn mc JOIN connections c ON c.member_b = mc.f
)
SELECT suggestion, count(*) AS mutuals
FROM second_edges se
WHERE suggestion <> 1023
  AND NOT EXISTS (SELECT 1 FROM my_conn mc WHERE mc.f = se.suggestion)
GROUP BY suggestion
ORDER BY mutuals DESC, suggestion
LIMIT 20;

-- Reads: job search and applications
-- @R06
-- Job search: open "data analyst" jobs in Bengaluru or remote, posted in the last 30 days of June 2026
SELECT j.job_id, j.title, c.company_name, j.workplace_type, j.min_salary_lpa, j.max_salary_lpa, j.posted_at
FROM jobs j
JOIN companies c ON c.company_id = j.company_id
WHERE j.status = 'OPEN'
  AND j.title ILIKE '%data analyst%'
  AND (j.city_id = 1 OR j.workplace_type = 'REMOTE')
  AND j.posted_at >= '2026-06-01'
ORDER BY j.posted_at DESC;

-- @R07
-- "Jobs for you": open jobs that need at least 2 of member 1023's skills
SELECT js.job_id, count(*) AS matching_skills
FROM job_skills js
JOIN member_skills ms ON ms.skill_id = js.skill_id AND ms.member_id = 1023
JOIN jobs j           ON j.job_id = js.job_id AND j.status = 'OPEN'
GROUP BY js.job_id
HAVING count(*) >= 2
ORDER BY matching_skills DESC, js.job_id DESC
LIMIT 25;

-- @R08
-- Recruiter: applicants of job 14075 by pipeline stage
SELECT a.status, count(*) AS applicants
FROM applications a
WHERE a.job_id = 14075
GROUP BY a.status
ORDER BY applicants DESC;

-- @R09
-- "My Jobs": member 1023's applications with their status
SELECT a.application_id, j.title, c.company_name, a.status, a.applied_at
FROM applications a
JOIN jobs j      ON j.job_id = a.job_id
JOIN companies c ON c.company_id = j.company_id
WHERE a.member_id = 1023
ORDER BY a.applied_at DESC;

-- Reads: invitations and profile engagement
-- @R10
-- Invitations tab: pending invitations received by member 1023
SELECT i.invitation_id, i.sender_id, m.first_name, m.last_name, i.note, i.sent_at
FROM invitations i
JOIN members m ON m.member_id = i.sender_id
WHERE i.recipient_id = 1023 AND i.status = 'PENDING'
ORDER BY i.sent_at DESC;

-- @R11
-- "Who viewed your profile": viewers of member 217 since April 2026 (private-mode viewers counted separately)
SELECT coalesce(v.viewer_id::text, 'Someone in private mode') AS viewer, count(*) AS views, max(v.viewed_at) AS last_view
FROM profile_views v
WHERE v.viewed_id = 217
  AND v.viewed_at >= '2026-04-01'
GROUP BY 1
ORDER BY last_view DESC;

-- @R12
-- Company page: current employees of Flipkart and their average tenure in years
SELECT c.company_name, count(*) AS current_employees,
       round(avg((DATE '2026-07-01' - p.start_date) / 365.25), 1) AS avg_tenure_years
FROM positions p
JOIN companies c ON c.company_id = p.company_id
WHERE c.company_name = 'Flipkart' AND p.end_date IS NULL
GROUP BY c.company_name;

-- @R13
-- Engagement: members who have never viewed anyone's profile (for a re-engagement nudge)
-- NOT EXISTS handles private-mode rows, whose viewer_id is NULL.
SELECT m.member_id, m.first_name, m.last_name
FROM members m
WHERE NOT EXISTS (
    SELECT 1 FROM profile_views v WHERE v.viewer_id = m.member_id
);

-- Reads: talent and career insights
-- @R14
-- Talent insights: average days from application to hire, per company (2026 hires)
SELECT c.company_name, count(*) AS hires,
       round(avg(EXTRACT(EPOCH FROM (a.status_updated_at - a.applied_at)) / 86400), 1) AS avg_days_to_hire
FROM applications a
JOIN jobs j      ON j.job_id = a.job_id
JOIN companies c ON c.company_id = j.company_id
WHERE a.status = 'HIRED'
  AND a.status_updated_at >= '2026-01-01'
GROUP BY c.company_name
HAVING count(*) >= 3
ORDER BY avg_days_to_hire;

-- @R15
-- Skill demand: skills most requested by jobs posted in 2026
-- This date range gives the planner a chance to use the posted_at index.
SELECT s.skill_name, count(*) AS jobs
FROM job_skills js
JOIN skills s ON s.skill_id = js.skill_id
JOIN jobs j   ON j.job_id = js.job_id
WHERE j.posted_at >= TIMESTAMPTZ '2026-01-01 00:00:00'
  AND j.posted_at <  TIMESTAMPTZ '2027-01-01 00:00:00'
GROUP BY s.skill_name
ORDER BY jobs DESC
LIMIT 20;

-- @R16
-- Salary insights: average advertised salary range per job title and city (2026 postings with salaries)
SELECT j.title, coalesce(ct.city_name, 'Remote') AS city, count(*) AS postings,
       round(avg(j.min_salary_lpa), 1) AS avg_min_lpa, round(avg(j.max_salary_lpa), 1) AS avg_max_lpa
FROM jobs j
LEFT JOIN cities ct ON ct.city_id = j.city_id
WHERE j.min_salary_lpa IS NOT NULL AND j.posted_at >= '2026-01-01'
GROUP BY j.title, coalesce(ct.city_name, 'Remote')
ORDER BY j.title, avg_max_lpa DESC NULLS LAST;

-- @R17
-- Talent flow: companies people joined right after leaving TCS
SELECT nxt.company_name, count(*) AS moved
FROM (
    SELECT p.member_id, p.company_id,
           lead(p.company_id) OVER (PARTITION BY p.member_id ORDER BY p.start_date) AS next_company_id
    FROM positions p
) t
JOIN companies cur ON cur.company_id = t.company_id AND cur.company_name = 'TCS'
JOIN companies nxt ON nxt.company_id = t.next_company_id
WHERE t.next_company_id <> t.company_id
GROUP BY nxt.company_name
ORDER BY moved DESC
LIMIT 15;

-- Reads: recruiter, employer, and platform reporting
-- @R18
-- Recruiter search: open-to-work Bengaluru members with SQL skill, most endorsed first
SELECT m.member_id, m.first_name, m.last_name, m.headline, ms.endorsements
FROM members m
JOIN member_skills ms ON ms.member_id = m.member_id
JOIN skills s         ON s.skill_id = ms.skill_id AND s.skill_name = 'SQL'
WHERE m.open_to_work AND m.city_id = 1
ORDER BY ms.endorsements DESC
LIMIT 50;

-- @R19
-- Employer report: open jobs and June 2026 applications of every IT Services company
-- Count jobs and applications by company once instead of rescanning for every company.
WITH open_jobs AS (
    SELECT company_id, count(*) AS open_jobs
    FROM jobs WHERE status = 'OPEN' GROUP BY company_id
), june_apps AS (
    SELECT j.company_id, count(*) AS june_applications
    FROM applications a JOIN jobs j ON j.job_id = a.job_id
    WHERE a.applied_at >= '2026-06-01'
    GROUP BY j.company_id
)
SELECT c.company_id, c.company_name,
       coalesce(oj.open_jobs, 0) AS open_jobs,
       coalesce(ja.june_applications, 0) AS june_applications
FROM companies c
LEFT JOIN open_jobs oj USING (company_id)
LEFT JOIN june_apps ja USING (company_id)
WHERE c.industry = 'IT Services'
ORDER BY june_applications DESC;

-- @R20
-- Platform analytics: applications per day and running total, June 2026
-- Keep the date test as a range so the applied_at index can help.
SELECT day, apps, sum(apps) OVER (ORDER BY day) AS running_total
FROM (
    SELECT applied_at::date AS day, count(*) AS apps
    FROM applications
    WHERE applied_at >= TIMESTAMPTZ '2026-06-01 00:00:00'
      AND applied_at <  TIMESTAMPTZ '2026-07-01 00:00:00'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Skills pages: the most-endorsed member for each skill
-- For each skill, use the first row in endorsement order.
SELECT s.skill_name, best.member_id, best.endorsements
FROM skills s
JOIN LATERAL (
    SELECT ms.member_id, ms.endorsements
    FROM member_skills ms
    WHERE ms.skill_id = s.skill_id
    ORDER BY ms.endorsements DESC, ms.member_id
    LIMIT 1
) best ON true
ORDER BY best.endorsements DESC;

-- @R22
-- Trust & safety console: all applications, newest first, page 4,001 (25 per page)
SELECT application_id, job_id, member_id, status, applied_at
FROM applications
ORDER BY applied_at DESC
OFFSET 100000
LIMIT 25;

-- @R23
-- Sign-in: find the member by email, ignoring case
SELECT member_id, first_name, last_name, is_premium
FROM members
WHERE lower(email) = 'yash.sharma1023@gmail.com';

-- Reads: growth and career insights
-- @R24
-- Growth: invitation acceptance rate of Premium vs free senders (2026)
SELECT m.is_premium, count(*) AS invitations,
       round(100.0 * count(*) FILTER (WHERE i.status = 'ACCEPTED') / count(*), 1) AS accept_pct
FROM invitations i
JOIN members m ON m.member_id = i.sender_id
WHERE i.sent_at >= '2026-01-01'
GROUP BY m.is_premium;

-- @R25
-- Career insights: members with a career break of more than 6 months between two positions
SELECT member_id, prev_end, start_date, start_date - prev_end AS gap_days
FROM (
    SELECT member_id, start_date,
           lag(end_date) OVER (PARTITION BY member_id ORDER BY start_date) AS prev_end
    FROM positions
) t
WHERE start_date - prev_end > 182
ORDER BY gap_days DESC, member_id
LIMIT 100;

-- Writes: transaction-safe benchmark cases (the final ROLLBACK restores the data)
-- @W01
-- "Easy Apply": member 1023 applies to job 14075
INSERT INTO applications (application_id, job_id, member_id, applied_at, easy_apply, status, status_updated_at)
VALUES (90000001, 14075, 1023, '2026-07-01 09:00:00+05:30', TRUE, 'APPLIED', '2026-07-01 09:00:00+05:30')
ON CONFLICT (job_id, member_id) DO NOTHING;

-- @W02
-- Member 1023 accepts their oldest pending invitation
-- Sorting by ID and taking one row selects the same oldest invitation as min().
UPDATE invitations
SET status = 'ACCEPTED', responded_at = '2026-07-01 09:10:00+05:30'
WHERE invitation_id = (
    SELECT invitation_id FROM invitations
    WHERE recipient_id = 1023 AND status = 'PENDING'
    ORDER BY invitation_id LIMIT 1
);

-- @W03
-- …and the new connection is stored once, smaller member id first
INSERT INTO connections (member_a, member_b, connected_at)
SELECT least(sender_id, recipient_id), greatest(sender_id, recipient_id), '2026-07-01 09:10:00+05:30'
FROM invitations
WHERE invitation_id = (SELECT min(invitation_id) FROM invitations WHERE recipient_id = 1023 AND status = 'PENDING')
ON CONFLICT DO NOTHING;

-- @W04
-- Nightly job: close every job whose closing date has passed
UPDATE jobs
SET status = 'CLOSED'
WHERE status = 'OPEN' AND closes_at < '2026-07-01 00:00:00+05:30';

-- @W05
-- Recruiter clean-up: reject applications to TCS jobs still unreviewed after 60 days
UPDATE applications a
SET status = 'REJECTED', status_updated_at = '2026-07-01 10:00:00+05:30'
FROM jobs j
JOIN companies c ON c.company_id = j.company_id
WHERE a.job_id = j.job_id
  AND c.company_name = 'TCS'
  AND a.status = 'APPLIED'
  AND a.applied_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30' - interval '60 days';

-- @END
ROLLBACK;
