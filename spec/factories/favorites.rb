FactoryBot.define do
  factory :favorite do
    association :user
    association :event
    reminders_enabled { true }

    trait :for_occurrence do
      event_occurrence { association :event_occurrence, event: event }
    end
  end
end
