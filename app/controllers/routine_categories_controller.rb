class RoutineCategoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template
  before_action :set_category, only: %i[
    edit
    update
    destroy
  ]

  def new
    @routine_category = @template.routine_categories.new
  end

  def create
    @routine_category =
      @template.routine_categories.new(category_params)

    if @routine_category.save
      redirect_to @template,
                  notice: "Categoria criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @routine_category.update(category_params)
      redirect_to @template,
                  notice: "Categoria atualizada."
    else
      render :edit,
             status: :unprocessable_entity
    end
  end

  def destroy
    @routine_category.destroy

    redirect_to @template,
                notice: "Categoria removida."
  end

  private

  def set_template
    @template = RoutineTemplate.visible_to(current_user).find(params[:routine_template_id])
    head :forbidden if @template.action_plan || !@template.manageable_by?(current_user)
  end

  def set_category
    @routine_category =
      @template.routine_categories.find(params[:id])
  end

  def category_params
    params.require(:routine_category)
          .permit(:name, :position)
  end
end
