FactoryBot.define do
  factory :event do
    association :user
    sequence(:title) { |n| "Event #{n}" }
    description { Faker::Lorem.paragraph }
    start_time { 2.days.from_now }
    duration { 120 }
    recurrence_type { "once" }
    status { "active" }
    visibility { "public" }
    open_to { "public" }
    max_occurrences { 5 }
    requires_mask { false }

    trait :weekly do
      recurrence_type { "weekly" }
      after(:build) do |event|
        schedule = Event.build_schedule(event.start_time, 'weekly', { days: [event.start_time.wday] })
        event.recurrence_rule = schedule.to_yaml
      end
    end

    trait :monthly do
      recurrence_type { "monthly" }
      after(:build) do |event|
        schedule = Event.build_schedule(event.start_time, 'monthly', {})
        event.recurrence_rule = schedule.to_yaml
      end
    end

    trait :members_only do
      visibility { "members" }
      open_to { "members" }
    end

    trait :private do
      visibility { "private" }
      open_to { "private" }
    end

    trait :postponed do
      status { "postponed" }
      postponed_until { 1.week.from_now }
      cancellation_reason { "Venue unavailable" }
    end

    trait :cancelled do
      status { "cancelled" }
      cancellation_reason { "Insufficient registrations" }
    end

    trait :with_banner do
      after(:create) do |event|
        event_image = event.event_images.create!(position: 0, in_pool: true)
        event_image.image.attach(
          io: StringIO.new('fake image content'),
          filename: 'banner.jpg',
          content_type: 'image/jpeg'
        )
        event.update!(fixed_event_image_id: event_image.id, image_selection_mode: 'fixed')
      end
    end

    trait :with_more_info do
      more_info_url { Faker::Internet.url }
    end

    trait :contactable do
      allow_host_contact { true }
    end

    trait :rsvp do
      rsvp_enabled { true }
      capacity { 2 }
      waitlist_enabled { true }
      waitlist_mode { 'first_come' }
    end
  end
end
