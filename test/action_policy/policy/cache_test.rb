# frozen_string_literal: true

require "test_helper"

require "stubs/in_memory_cache"

class TestCache < Minitest::Test
  class TestPolicy
    include ActionPolicy::Policy::Core
    include ActionPolicy::Policy::Authorization
    include ActionPolicy::Policy::Reasons
    include ActionPolicy::Policy::Cache

    self.identifier = :test

    class << self
      attr_accessor :managed_count, :shown_count, :saved_count, :custom_count

      def reset
        @managed_count = 0
        @shown_count = 0
        @saved_count = 0
        @custom_count = 0
      end
    end

    reset

    authorize :user

    cache :manage?, :save?

    def manage?
      self.class.managed_count += 1

      user.admin? && !record.admin?
    end

    def show?
      self.class.shown_count += 1

      user.admin? || !record.admin?
    end

    def save?
      self.class.saved_count += 1
      allowed_to?(:manage?)
    end

    def create?
      cache(user, record, :custom) do
        self.class.custom_count += 1
        true
      end
    end
  end

  class MultipleContextPolicy < TestPolicy
    reset

    authorize :account

    cache :show?
  end

  class CacheableUser < User
    def policy_class
      UserPolicy
    end

    def policy_cache_key
      "user/#{name}"
    end

    def admin?
      name.start_with?("admin")
    end
  end

  def setup
    ActionPolicy.cache_store = InMemoryCache.new
    @guest = CacheableUser.new("guest")
  end

  def teardown
    TestPolicy.reset
    MultipleContextPolicy.reset
    ActionPolicy.cache_store = nil
  end

  attr_reader :guest

  def test_cache
    user = CacheableUser.new("admin")

    policy = TestPolicy.new record: guest, user: user

    assert policy.apply(:manage?)
    assert policy.apply(:manage?)
    assert policy.apply(:show?)
    assert policy.apply(:show?)

    assert_equal 1, TestPolicy.managed_count
    assert_equal 2, TestPolicy.shown_count

    policy_2 = TestPolicy.new record: guest, user: user

    assert policy_2.apply(:manage?)
    assert policy_2.apply(:show?)

    assert_equal 1, TestPolicy.managed_count
    assert_equal 3, TestPolicy.shown_count
  end

  def test_custom_cache
    user = CacheableUser.new("guest")

    policy = TestPolicy.new record: nil, user: user

    assert policy.apply(:create?)
    assert policy.apply(:create?)

    assert_equal 1, TestPolicy.custom_count

    policy_2 = TestPolicy.new record: nil, user: user

    assert policy_2.apply(:create?)

    assert_equal 1, TestPolicy.custom_count
  end

  def test_cache_with_reasons
    user = CacheableUser.new("guest")

    policy = TestPolicy.new record: guest, user: user

    refute policy.apply(:save?)
    assert_equal({test: [:manage?]}, policy.result.reasons.details)

    policy = TestPolicy.new record: guest, user: user

    refute policy.apply(:save?)
    assert_equal({test: [:manage?]}, policy.result.reasons.details)

    assert_equal 1, TestPolicy.managed_count
    assert_equal 1, TestPolicy.saved_count
  end

  def test_cache_with_different_records
    user = CacheableUser.new("admin")

    policy = TestPolicy.new record: guest, user: user

    assert policy.apply(:manage?)

    assert_equal 1, TestPolicy.managed_count

    policy_2 = TestPolicy.new record: CacheableUser.new("guest_2"), user: user

    assert policy_2.apply(:manage?)
    assert_equal 2, TestPolicy.managed_count
  end

  def test_cache_with_different_contexts
    user = CacheableUser.new("admin")

    policy = TestPolicy.new record: guest, user: user

    assert policy.apply(:manage?)

    assert_equal 1, TestPolicy.managed_count

    policy_2 = TestPolicy.new record: guest, user: CacheableUser.new("admin_2")

    assert policy_2.apply(:manage?)
    assert_equal 2, TestPolicy.managed_count
  end

  def test_with_multiple_contexts
    user = CacheableUser.new("admin")

    policy = MultipleContextPolicy.new record: guest, user: user, account: "test"

    assert policy.apply(:manage?)
    assert policy.apply(:manage?)
    assert policy.apply(:show?)
    assert policy.apply(:show?)

    assert_equal 1, MultipleContextPolicy.managed_count
    assert_equal 1, MultipleContextPolicy.shown_count

    policy_2 = MultipleContextPolicy.new record: guest, user: CacheableUser.new("admin"), account: :test

    assert policy_2.apply(:manage?)
    assert policy_2.apply(:show?)

    assert_equal 1, MultipleContextPolicy.managed_count
    assert_equal 1, MultipleContextPolicy.shown_count
  end

  def test_with_different_multiple_contexts
    user = CacheableUser.new("admin")

    policy = MultipleContextPolicy.new record: guest, user: user, account: "test"

    assert policy.apply(:manage?)
    assert policy.apply(:manage?)

    assert_equal 1, MultipleContextPolicy.managed_count

    policy_2 = MultipleContextPolicy.new record: guest, user: CacheableUser.new("admin"), account: "test_2"

    assert policy_2.apply(:manage?)
    assert_equal 2, MultipleContextPolicy.managed_count
  end
end
