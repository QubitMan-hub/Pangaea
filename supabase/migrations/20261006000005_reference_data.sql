-- Reference data the app needs in every environment (not user content).

-- The frontier: where plots wait until enough similar ones exist to found a
-- new region (brief 5.1 step 5). It sits at the world origin.
insert into public.regions (label, is_frontier, center_x, center_y)
values ('Frontier', true, 0, 0);

-- MVP missions (brief 5.3). Reward points are placeholders to tune in Phase 4.
insert into public.missions (slug, title, description, reward_points)
values
  (
    'thoughtful-neighbor',
    'Be a thoughtful neighbor',
    'Leave thoughtful comments on three neighboring plots.',
    30
  ),
  (
    'answer-a-question',
    'Answer a question',
    'Answer a question someone pinned on their plot.',
    20
  ),
  (
    'explorer',
    'Explorer',
    'Visit a region you have never visited and leave a note.',
    20
  ),
  (
    'complete-your-plot',
    'Complete your plot',
    'Put at least three items on your plot.',
    10
  );
