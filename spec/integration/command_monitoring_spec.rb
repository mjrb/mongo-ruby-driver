require 'spec_helper'

class TestCommandMonitoringSubscriber
  def initialize
    @started_events = []
    @succeeded_events = []
    @failed_events = []
  end

  attr_reader :started_events, :succeeded_events, :failed_events

  def started(event)
    @started_events << event
  end

  def succeeded(event)
    @succeeded_events << event
  end

  def failed(event)
    @failed_events << event
  end
end

describe 'Command monitoring' do
  let(:subscriber) { TestCommandMonitoringSubscriber.new }

  before do
    Mongo::Monitoring::Global.subscribe(Mongo::Monitoring::COMMAND, subscriber)
  end

  after do
    Mongo::Monitoring::Global.unsubscribe(Mongo::Monitoring::COMMAND, subscriber)
  end

  let(:client) { Mongo::Client.new(authorized_client.cluster.addresses.map(&:to_s), authorized_client.options) }

  it 'notifies on successful commands' do
    result = client.database.command(:ismaster => 1)
    expect(result.documents.first['ismaster']).to be true

    started_events = subscriber.started_events.select do |event|
      event.command_name == 'ismaster'
    end
    expect(started_events.length).to eql(1)
    started_event = started_events.first
    expect(started_event.command_name).to eql('ismaster')
    expect(started_event.address).to be_a(Mongo::Address)

    succeeded_events = subscriber.succeeded_events.select do |event|
      event.command_name == 'ismaster'
    end
    expect(succeeded_events.length).to eql(1)
    succeeded_event = succeeded_events.first
    expect(succeeded_event.command_name).to eql('ismaster')
    expect(succeeded_event.reply).to be_a(BSON::Document)
    expect(succeeded_event.reply['ismaster']).to eql(true)
    expect(succeeded_event.address).to be_a(Mongo::Address)
    expect(succeeded_event.duration).to be_a(Float)

    expect(subscriber.failed_events.length).to eql(0)
  end

  it 'notifies on failed commands' do
    expect do
      result = client.database.command(:bogus => 1)
    end.to raise_error(Mongo::Error::OperationFailure, /no such c(om)?m(an)?d/)

    started_events = subscriber.started_events.select do |event|
      event.command_name == 'bogus'
    end
    expect(started_events.length).to eql(1)
    started_event = started_events.first
    expect(started_event.command_name).to eql('bogus')
    expect(started_event.address).to be_a(Mongo::Address)

    succeeded_events = subscriber.succeeded_events.select do |event|
      event.command_name == 'ismaster'
    end
    expect(succeeded_events.length).to eql(0)

    failed_events = subscriber.failed_events.select do |event|
      event.command_name == 'bogus'
    end
    expect(failed_events.length).to eql(1)
    failed_event = failed_events.first
    expect(failed_event.command_name).to eql('bogus')
    expect(failed_event.message).to match(/no such c(om)?m(an)?d/)
    expect(failed_event.address).to be_a(Mongo::Address)
    expect(failed_event.duration).to be_a(Float)
  end
end
