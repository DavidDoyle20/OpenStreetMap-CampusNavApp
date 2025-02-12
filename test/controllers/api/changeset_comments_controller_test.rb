require "test_helper"

module Api
  class ChangesetCommentsControllerTest < ActionDispatch::IntegrationTest
    ##
    # test all routes which lead to this controller
    def test_routes
      assert_routing(
        { :path => "/api/0.6/changeset/1/comment", :method => :post },
        { :controller => "api/changeset_comments", :action => "create", :id => "1" }
      )
      assert_routing(
        { :path => "/api/0.6/changeset/1/comment.json", :method => :post },
        { :controller => "api/changeset_comments", :action => "create", :id => "1", :format => "json" }
      )
      assert_routing(
        { :path => "/api/0.6/changeset/comment/1/hide", :method => :post },
        { :controller => "api/changeset_comments", :action => "destroy", :id => "1" }
      )
      assert_routing(
        { :path => "/api/0.6/changeset/comment/1/hide.json", :method => :post },
        { :controller => "api/changeset_comments", :action => "destroy", :id => "1", :format => "json" }
      )
      assert_routing(
        { :path => "/api/0.6/changeset/comment/1/unhide", :method => :post },
        { :controller => "api/changeset_comments", :action => "restore", :id => "1" }
      )
      assert_routing(
        { :path => "/api/0.6/changeset/comment/1/unhide.json", :method => :post },
        { :controller => "api/changeset_comments", :action => "restore", :id => "1", :format => "json" }
      )
    end

    def test_create_by_unauthorized
      assert_no_difference "ChangesetComment.count" do
        post changeset_comment_path(create(:changeset, :closed), :text => "This is a comment")
        assert_response :unauthorized
      end
    end

    def test_create_on_missing_changeset
      assert_no_difference "ChangesetComment.count" do
        post changeset_comment_path(999111, :text => "This is a comment"), :headers => bearer_authorization_header
        assert_response :not_found
      end
    end

    def test_create_on_open_changeset
      assert_no_difference "ChangesetComment.count" do
        post changeset_comment_path(create(:changeset), :text => "This is a comment"), :headers => bearer_authorization_header
        assert_response :conflict
      end
    end

    def test_create_without_text
      assert_no_difference "ChangesetComment.count" do
        post changeset_comment_path(create(:changeset, :closed)), :headers => bearer_authorization_header
        assert_response :bad_request
      end
    end

    def test_create_with_empty_text
      assert_no_difference "ChangesetComment.count" do
        post changeset_comment_path(create(:changeset, :closed), :text => ""), :headers => bearer_authorization_header
        assert_response :bad_request
      end
    end

    def test_create_when_not_agreed_to_terms
      user = create(:user, :terms_agreed => nil)
      auth_header = bearer_authorization_header user
      changeset = create(:changeset, :closed)

      assert_difference "ChangesetComment.count", 0 do
        post changeset_comment_path(changeset), :params => { :text => "This is a comment" }, :headers => auth_header
        assert_response :forbidden
      end
    end

    def test_create_with_write_api_scope
      user = create(:user)
      auth_header = bearer_authorization_header user, :scopes => %w[write_api]
      changeset = create(:changeset, :closed)

      assert_difference "ChangesetComment.count", 1 do
        post changeset_comment_path(changeset), :params => { :text => "This is a comment" }, :headers => auth_header
        assert_response :success
      end

      comment = ChangesetComment.last
      assert_equal changeset.id, comment.changeset_id
      assert_equal user.id, comment.author_id
      assert_equal "This is a comment", comment.body
      assert comment.visible
    end

    def test_create_on_changeset_with_no_subscribers
      changeset = create(:changeset, :closed)
      auth_header = bearer_authorization_header

      assert_difference "ChangesetComment.count", 1 do
        assert_no_difference "ActionMailer::Base.deliveries.size" do
          perform_enqueued_jobs do
            post changeset_comment_path(changeset, :text => "This is a comment"), :headers => auth_header
            assert_response :success
          end
        end
      end
    end

    def test_create_on_changeset_with_commenter_subscriber
      user = create(:user)
      changeset = create(:changeset, :closed, :user => user)
      changeset.subscribers << user
      auth_header = bearer_authorization_header user

      assert_difference "ChangesetComment.count", 1 do
        assert_no_difference "ActionMailer::Base.deliveries.size" do
          perform_enqueued_jobs do
            post changeset_comment_path(changeset, :text => "This is a comment"), :headers => auth_header
            assert_response :success
          end
        end
      end
    end

    def test_create_on_changeset_with_invisible_subscribers
      changeset = create(:changeset, :closed)
      changeset.subscribers << create(:user, :suspended)
      changeset.subscribers << create(:user, :deleted)
      auth_header = bearer_authorization_header

      assert_difference "ChangesetComment.count", 1 do
        assert_no_difference "ActionMailer::Base.deliveries.size" do
          perform_enqueued_jobs do
            post changeset_comment_path(changeset, :text => "This is a comment"), :headers => auth_header
            assert_response :success
          end
        end
      end
    end

    def test_create_on_changeset_with_changeset_creator_subscriber
      creator_user = create(:user)
      changeset = create(:changeset, :closed, :user => creator_user)
      changeset.subscribers << creator_user
      commenter_user = create(:user)
      auth_header = bearer_authorization_header commenter_user

      assert_difference "ChangesetComment.count", 1 do
        assert_difference "ActionMailer::Base.deliveries.size", 1 do
          perform_enqueued_jobs do
            post changeset_comment_path(changeset, :text => "This is a comment"), :headers => auth_header
            assert_response :success
          end
        end
      end

      email = ActionMailer::Base.deliveries.first
      assert_equal 1, email.to.length
      assert_equal "[OpenStreetMap] #{commenter_user.display_name} has commented on one of your changesets", email.subject
      assert_equal creator_user.email, email.to.first

      ActionMailer::Base.deliveries.clear
    end

    def test_create_on_changeset_with_changeset_creator_and_other_user_subscribers
      creator_user = create(:user)
      changeset = create(:changeset, :closed, :user => creator_user)
      changeset.subscribers << creator_user
      other_user = create(:user)
      changeset.subscribers << other_user
      commenter_user = create(:user)
      auth_header = bearer_authorization_header commenter_user

      assert_difference "ChangesetComment.count", 1 do
        assert_difference "ActionMailer::Base.deliveries.size", 2 do
          perform_enqueued_jobs do
            post changeset_comment_path(changeset, :text => "This is a comment"), :headers => auth_header
            assert_response :success
          end
        end
      end

      email = ActionMailer::Base.deliveries.find { |e| e.to.first == creator_user.email }
      assert_not_nil email
      assert_equal 1, email.to.length
      assert_equal "[OpenStreetMap] #{commenter_user.display_name} has commented on one of your changesets", email.subject

      email = ActionMailer::Base.deliveries.find { |e| e.to.first == other_user.email }
      assert_not_nil email
      assert_equal 1, email.to.length
      assert_equal "[OpenStreetMap] #{commenter_user.display_name} has commented on a changeset you are interested in", email.subject

      ActionMailer::Base.deliveries.clear
    end

    ##
    # create comment rate limit for new users
    def test_create_by_new_user_with_rate_limit
      changeset = create(:changeset, :closed)
      user = create(:user)

      auth_header = bearer_authorization_header user

      assert_difference "ChangesetComment.count", Settings.initial_changeset_comments_per_hour do
        1.upto(Settings.initial_changeset_comments_per_hour) do |count|
          post changeset_comment_path(changeset, :text => "Comment #{count}"), :headers => auth_header
          assert_response :success
        end
      end

      assert_no_difference "ChangesetComment.count" do
        post changeset_comment_path(changeset, :text => "One comment too many"), :headers => auth_header
        assert_response :too_many_requests
      end
    end

    ##
    # create comment rate limit for experienced users
    def test_create_by_experienced_user_with_rate_limit
      changeset = create(:changeset, :closed)
      user = create(:user)
      create_list(:changeset_comment, Settings.comments_to_max_changeset_comments, :author_id => user.id, :created_at => Time.now.utc - 1.day)

      auth_header = bearer_authorization_header user

      assert_difference "ChangesetComment.count", Settings.max_changeset_comments_per_hour do
        1.upto(Settings.max_changeset_comments_per_hour) do |count|
          post changeset_comment_path(changeset, :text => "Comment #{count}"), :headers => auth_header
          assert_response :success
        end
      end

      assert_no_difference "ChangesetComment.count" do
        post changeset_comment_path(changeset, :text => "One comment too many"), :headers => auth_header
        assert_response :too_many_requests
      end
    end

    ##
    # create comment rate limit for reported users
    def test_create_by_reported_user_with_rate_limit
      changeset = create(:changeset, :closed)
      user = create(:user)
      create(:issue_with_reports, :reportable => user, :reported_user => user)

      auth_header = bearer_authorization_header user

      assert_difference "ChangesetComment.count", Settings.initial_changeset_comments_per_hour / 2 do
        1.upto(Settings.initial_changeset_comments_per_hour / 2) do |count|
          post changeset_comment_path(changeset, :text => "Comment #{count}"), :headers => auth_header
          assert_response :success
        end
      end

      assert_no_difference "ChangesetComment.count" do
        post changeset_comment_path(changeset, :text => "One comment too many"), :headers => auth_header
        assert_response :too_many_requests
      end
    end

    ##
    # create comment rate limit for moderator users
    def test_create_by_moderator_user_with_rate_limit
      changeset = create(:changeset, :closed)
      user = create(:moderator_user)

      auth_header = bearer_authorization_header user

      assert_difference "ChangesetComment.count", Settings.moderator_changeset_comments_per_hour do
        1.upto(Settings.moderator_changeset_comments_per_hour) do |count|
          post changeset_comment_path(changeset, :text => "Comment #{count}"), :headers => auth_header
          assert_response :success
        end
      end

      assert_no_difference "ChangesetComment.count" do
        post changeset_comment_path(changeset, :text => "One comment too many"), :headers => auth_header
        assert_response :too_many_requests
      end
    end

    def test_hide_by_unauthorized
      comment = create(:changeset_comment)

      post changeset_comment_hide_path(comment)

      assert_response :unauthorized
      assert comment.reload.visible
    end

    def test_hide_by_normal_user
      comment = create(:changeset_comment)
      auth_header = bearer_authorization_header

      post changeset_comment_hide_path(comment), :headers => auth_header

      assert_response :forbidden
      assert comment.reload.visible
    end

    def test_hide_missing_comment
      auth_header = bearer_authorization_header create(:moderator_user)

      post changeset_comment_hide_path(999111), :headers => auth_header

      assert_response :not_found
    end

    ##
    # test hide comment succes
    def test_hide
      comment = create(:changeset_comment)
      assert comment.visible

      auth_header = bearer_authorization_header create(:moderator_user)

      post changeset_comment_hide_path(comment), :headers => auth_header
      assert_response :success
      assert_not comment.reload.visible
    end

    ##
    # test unhide comment fail
    def test_unhide_fail
      # unauthorized
      comment = create(:changeset_comment, :visible => false)
      assert_not comment.visible

      post changeset_comment_unhide_path(comment)
      assert_response :unauthorized
      assert_not comment.reload.visible

      auth_header = bearer_authorization_header

      # not a moderator
      post changeset_comment_unhide_path(comment), :headers => auth_header
      assert_response :forbidden
      assert_not comment.reload.visible

      auth_header = bearer_authorization_header create(:moderator_user)

      # bad comment id
      post changeset_comment_unhide_path(999111), :headers => auth_header
      assert_response :not_found
      assert_not comment.reload.visible
    end

    ##
    # test unhide comment succes
    def test_unhide
      comment = create(:changeset_comment, :visible => false)
      assert_not comment.visible

      auth_header = bearer_authorization_header create(:moderator_user)

      post changeset_comment_unhide_path(comment), :headers => auth_header
      assert_response :success
      assert comment.reload.visible
    end
  end
end
