class RoutineCommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine_value
  before_action :set_comment, only: :destroy

  def index
    render json: {
      comments: serialized_comments,
      count: @routine_value.routine_comments.size
    }
  end

  def create
    comment = @routine_value.routine_comments.new(comment_params)
    comment.user = current_user

    if comment.save
      render json: {
        comment: serialized_comment(comment),
        count: @routine_value.routine_comments.count
      }, status: :created
    else
      render json: {
        errors: comment.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    return head :forbidden unless can_destroy_comment?

    @comment.destroy!

    render json: {
      count: @routine_value.routine_comments.count
    }
  end

  private

  def set_routine_value
    @routine_value =
      RoutineValue
        .includes(routine_comments: :user)
        .find(params[:routine_value_id])
  end

  def set_comment
    @comment =
      @routine_value
        .routine_comments
        .find(params[:id])
  end

  def serialized_comments
    @routine_value
      .routine_comments
      .sort_by(&:created_at)
      .map do |comment|
        serialized_comment(comment)
      end
  end

  def serialized_comment(comment)
    {
      id: comment.id,
      body: comment.body,
      user_name: routine_comment_user_name(comment.user),
      created_at: comment.created_at.strftime("%d/%m/%Y %H:%M"),
      can_destroy: comment.user_id == current_user.id || current_user.admin?
    }
  end

  def routine_comment_user_name(user)
    return user.name if user.respond_to?(:name) && user.name.present?
    return user.email if user.email.present?

    "Usuário ##{user.id}"
  end

  def can_destroy_comment?
    @comment.user_id == current_user.id || current_user.admin?
  end

  def comment_params
    params
      .require(:routine_comment)
      .permit(:body)
  end
end
