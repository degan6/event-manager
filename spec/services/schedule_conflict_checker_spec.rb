require 'rails_helper'

RSpec.describe ScheduleConflictChecker do
  # Keep this ahead of "now". Finished events are ignored, so a fixed date
  # stops matching once the calendar passes it.
  let(:start_time) { 3.weeks.from_now.change(hour: 18, min: 0, sec: 0) }

  before { SiteConfig.current.update!(default_conflict_buffer_minutes: 60) }

  def result_for(event)
    described_class.for_event(event)
  end

  describe 'exclusive events' do
    let!(:exclusive) do
      create(:event, title: 'Open House', start_time: start_time, duration: 60,
                     exclusive_status: 'approved', conflict_buffer_minutes: 60)
    end

    it 'blocks an event during the exclusive event and its buffer' do
      during = build(:event, start_time: start_time, duration: 60)
      before_buffer = build(:event, start_time: start_time - 30.minutes, duration: 30)
      after_buffer = build(:event, start_time: start_time + 90.minutes, duration: 30)

      expect(result_for(during).blocks.map(&:event)).to eq([exclusive])
      expect(result_for(before_buffer).blocks.map(&:event)).to eq([exclusive])
      expect(result_for(after_buffer).blocks.map(&:event)).to eq([exclusive])
    end

    it 'allows an event that only touches the edge of the buffer' do
      touching = build(:event, start_time: start_time - 2.hours, duration: 60)

      expect(result_for(touching).blocks).to be_empty
    end

    it 'uses the site default buffer when the event has none' do
      exclusive.update!(conflict_buffer_minutes: nil)
      inside_default = build(:event, start_time: start_time - 30.minutes, duration: 30)
      outside_default = build(:event, start_time: start_time - 90.minutes, duration: 30)

      expect(result_for(inside_default).blocks.map(&:event)).to eq([exclusive])
      expect(result_for(outside_default).blocks).to be_empty
    end

    it 'does not block for a pending exclusive event' do
      exclusive.update!(exclusive_status: 'pending')
      candidate = build(:event, start_time: start_time, duration: 60)
      result = result_for(candidate)

      expect(result.blocks).to be_empty
      expect(result.cautions.map(&:kind)).to eq([:pending_exclusive])
    end

    it 'ignores drafts, cancelled occurrences, and soft-deleted events' do
      exclusive.update!(draft: true)
      expect(result_for(build(:event, start_time: start_time)).blocks).to be_empty

      exclusive.update!(draft: false)
      exclusive.occurrences.each { |occurrence| occurrence.update!(status: 'cancelled') }
      expect(result_for(build(:event, start_time: start_time)).blocks).to be_empty

      exclusive.occurrences.each { |occurrence| occurrence.update!(status: 'active') }
      exclusive.soft_delete
      expect(result_for(build(:event, start_time: start_time)).blocks).to be_empty
    end

    it 'uses an occurrence duration override' do
      exclusive.occurrences.first.update!(duration_override: 180)
      later = build(:event, start_time: start_time + 2.hours, duration: 30)

      expect(result_for(later).blocks.map(&:event)).to eq([exclusive])
    end

  end

  it 'blocks a booking inside a long exclusive event that started before the search pad' do
    create(:event, title: 'Build Out', start_time: start_time - 2.days, duration: 3 * 24 * 60,
                   exclusive_status: 'approved', conflict_buffer_minutes: 60)
    candidate = build(:event, start_time: start_time, duration: 60)

    expect(result_for(candidate).blocks.map { |conflict| conflict.event.title }).to eq(['Build Out'])
  end

  it 'lists ordinary events a new exclusive event would cover without blocking that exclusive event' do
    ordinary = create(:event, title: 'Workshop', start_time: start_time, duration: 60)
    candidate = build(:event, start_time: start_time, duration: 60, exclusive_status: 'approved',
                              conflict_buffer_minutes: 60)

    result = result_for(candidate)

    expect(result.blocks).to be_empty
    expect(result.covered.map(&:event)).to include(ordinary)
  end

  describe 'busy events' do
    let!(:busy) do
      create(:event, title: 'Members Night', start_time: start_time, duration: 60, busy: true,
                     conflict_buffer_minutes: 60)
    end

    it 'cautions in both directions and does not block' do
      arriving = build(:event, start_time: start_time - 30.minutes, duration: 60)
      expect(result_for(arriving).blocks).to be_empty
      expect(result_for(arriving).cautions.map(&:event)).to eq([busy])

      covering = build(:event, start_time: start_time, duration: 60, busy: true, conflict_buffer_minutes: 60)
      other = create(:event, title: 'Quiet Meetup', start_time: start_time + 30.minutes, duration: 60)
      expect(result_for(covering).cautions.map(&:event)).to include(other)
    end
  end

  describe 'nearby events' do
    it 'keeps the 15 minute warning when neither event is busy or exclusive' do
      first = create(:event, start_time: start_time, duration: 60)
      second = build(:event, start_time: start_time + 10.minutes, duration: 60)

      result = result_for(second)

      expect(result.blocks).to be_empty
      expect(result.cautions).to be_empty
      expect(result.nearby.map(&:event)).to eq([first])
    end

    it 'does not also list an exclusive event as nearby' do
      create(:event, start_time: start_time, duration: 60, exclusive_status: 'approved')
      result = result_for(build(:event, start_time: start_time, duration: 60))

      expect(result.blocks.size).to eq(1)
      expect(result.nearby).to be_empty
    end
  end
end
