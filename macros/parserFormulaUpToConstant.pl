loadMacros("MathObjects.pl");

sub _parserFormulaUpToConstant_init {FormulaUpToConstant::Init()}

=head1 FormulaUpToConstant();

 ######################################################################
 #
 #  This file implements the FormulaUpToConstant object, which is
 #  a formula that is only unique up to a constant (i.e., this is
 #  an anti-derivative). Students must include the "+C" as part of
 #  their answers, but they can use any (single-letter) constant that
 #  they want, and it doesn't have to be the one the professor used.
 #
 #  To use FormulaWithConstat objects, load this macro file at the
 #  top of your problem:
 #
 #    loadMacros("parserFormulaUpToConstant.pl");
 #
 #  then create a formula with constant as follows:
 #
 #    $f = FormulaUpToConstant("sin(x)+C");
 #
 #  Note that the C should NOT already be a variable in the Context;
 #  the FormulaUpToConstant object will handle adding it in for
 #  you.  If you don't include a constant in your formula (i.e., if
 #  all the variables that you used are already in your Context,
 #  then the FormulaUpToConstant object will add "+C" for you.
 #
 #  The FormulaUpToConstant should work like any normal Formula,
 #  and in particular, you use $f->cmp to get its answer checker.
 #
 #    ANS($f->cmp);
 #
 #  Note that the FormulaUpToConstant object creates its only private
 #  copy of the current Context (so that it can add variables without
 #  affecting the rest of the problem).  You should not notice this
 #  in general, but if you need to access that context, use $f->{context}.
 #  E.g.
 #
 #    Context($f->{context});
 #
 #  would make the current context the one being used by the
 #  FormulaUpToConstant, while
 #
 #    $f->{context}->variables->names
 #
 #  would return a list of the variables in the private context.
 #
 #  To get the name of the constant in use in the formula,
 #  use
 #
 #    $f->constant.
 #
 #  If you combine a FormulaUpToConstant with other formulas,
 #  the result will be a new FormulaUpToConstant object, with
 #  a new Context, and potentially a new + C added to it.  This
 #  is likely not what you want.  Instead, you should convert
 #  back to a Formula first, then combine with other objects,
 #  then convert back to a FormulaUpToConstant, if necessary.
 #  To do this, use the removeConstant() method:
 #
 #    $f = FormulaUpToConstant("sin(x)+C");
 #    $g = Formula("cos(x)");
 #    $h = $f->removeConstant + $g;  # $h will be "sin(x)+cos(x)"
 #    $h = FormulaUpToConstant($h);  # $h will be "sin(x)+cos(x)+C"
 #
 #  The answer evaluator by default will give "helpful" messages
 #  to the student when the "+ C" is left out.  You can turn off
 #  these messages using the showHints option to the cmp() method:
 #
 #    ANS($f->cmp(showHints => 0));
 #
 ######################################################################

=cut

package FormulaUpToConstant;
@ISA = ('Value::Formula');

sub Init {
  main::PG_restricted_eval('sub FormulaUpToConstant {FormulaUpToConstant->new(@_)}');
}

#
#  Create an instance of a FormulaUpToConstant.  If no constant
#  is supplied, we add C ourselves.
#
sub new {
  my $self = shift; my $class = ref($self) || $self;
  #
  #  Copy the context (so we can modify it) and
  #  replace the usual Variable object with our own.
  #
  my $context = (Value::isContext($_[0]) ? shift : $self->context)->copy;
  $context->{parser}{Variable} = 'FormulaUpToConstant::Variable';
  #
  #  Create a formula from the user's input.
  #
  my $f = main::Formula($context,@_);
  #
  #  If it doesn't have a constant already, add one.
  #  (should check that C isn't already in use, and look
  #   up the first free name, but we'll cross our fingers
  #   for now.  Could look through the defined variables
  #   to see if there is already an arbitraryConstant
  #   and use that.)
  #
  unless ($f->{constant}) {$f = $f + "C", $f->{constant} = "C"}
  #
  #  Check that the formula is linear in C.
  #
  my $n = $f->D($f->{constant});
  Value->Error("Your formula isn't linear in the arbitrary constant '%s'",$f->{constant})
    unless $n->isConstant;
  #
  #  Make a version with an adaptive parameter for use in the
  #  comparison later on.  We could like n0*C, but already have $n
  #  copies of C, so remove them.  That way, n0 will be 0 when there
  #  are no C's in the student answer during the adaptive comparison.
  #  (Again, should really check that n0 is not in use already)
  #
  my $n0 = $context->variables->get("n0");
  $context->variables->add(n0=>'Parameter') unless $n0 and $n0->{parameter};
  $f->{adapt} = $f + "(n0-$n)$f->{constant}";
  return bless $f, $class;
}

##################################################
#
#  Remember that compare implements the overloaded perl <=> operator,
#  and $a <=> $b is -1 when $a < $b, 0 when $a == $b and 1 when $a > $b.
#  In our case, we only care about equality, so we will return 0 when
#  equal and other numbers to indicate the reason they are not equal
#  (this can be used by the answer checker to print helpful messages)
#
sub compare {
  my ($l,$r) = @_; my $self = $l; my $context = $self->context;
  $r = Value::makeValue($r,context=>$context);
  #
  #  Not equal if the student value is constant or has no + C
  #
  return 2 if !Value::isFormula($r);
  return 3 if !defined($r->{constant});
  #
  #  If constants aren't the same, substitute the professor's in the student answer.
  #
  $r = $r->substitute($r->{constant}=>$l->{constant}) unless $r->{constant} eq $l->{constant};
  #
  #  Compare with adaptive parameters to see if $l + n0 C = $r for some n0.
  #
  return -1 unless $l->{adapt} == $r;
  #
  #  Check that n0 is non-zero (i.e., there is a multiple of C in the student answer)
  #  (remember: return value of 0 is equal, and non-zero is unequal)
  #
  return abs($context->variables->get("n0")->{value}) < $context->flag("zeroLevelTol");
}

#
#  Show hints by default
#
sub cmp_defaults {((shift)->SUPER::cmp_defaults,showHints => 1)};

#
#  Add useful messages, if the author requested them
#
sub cmp_postprocess {
  my $self = shift; my $ans = shift;
  $self->SUPER::cmp_postprocess($ans);
  return unless $ans->{score} == 0 && !$ans->{isPreview};
  return if $ans->{ans_message} || !$self->getFlag("showHints");
  my $result = $ans->{correct_value} <=> $ans->{student_value};  # compare encodes the reason in the result
  $self->cmp_Error($ans,"Note: there is always more than one posibility") if $result == 2 || $result == 3;
  $self->cmp_Error($ans,"Your answer is not the most general solution")
    if $result == 1 || ($result == 3 && $self->removeConstant == $ans->{student_value});
}

#
#  Get the name of the constant
#
sub constant {(shift)->{constant}}

#
#  Remove the constant and return a Formula object
#
sub removeConstant {
  my $self = shift;
  main::Formula($self->substitute($self->{constant}=>0))->reduce;
}

#
#  Override the differentiation so that we always return
#  a Formula, not a FormulaUpToConstant (we don't want to
#  add the C in again).
#
sub D {
  my $self = shift;
  $self->removeConstant->D(@_);
}

######################################################################
#
#  This class repalces the Parser::Variable class, and its job
#  is to look for new constants that aren't in the context,
#  and add them in.  This allows students to use ANY constant
#  they want, and a different one from the professor.  We check
#  that the student only used ONE arbitrary constant, however.
#
package FormulaUpToConstant::Variable;
our @ISA = ('Parser::Variable');

sub new {
  my $self = shift; my $class = ref($self) || $self;
  my $equation = shift; my $variables = $equation->{context}{variables};
  my ($name,$ref) = @_; my $def = $variables->{$name};
  #
  #  If the variable is not already in the context, add it
  #    and mark it as an arbitrary constant (for later reference)
  #
  if (!defined($def) && length($name) eq 1) {
    $equation->{context}->variables->add($name => 'Real');
    $equation->{context}->variables->set($name => {arbitraryConstant => 1});
    $def = $variables->{$name};
  }
  #
  #  If the variable is an arbitrary constant
  #    Error if we already have a constant and it's not this one.
  #    Save the constant so we can check with it later.
  #
  if ($def && $def->{arbitraryConstant}) {
    $equation->Error(["Your formula shouldn't have two arbitrary constants"],$ref)
      if $equation->{constant} and $name ne $equation->{constant};
    $equation->{constant} = $name;
  }
  #
  #  Do the usual Variable stuff.
  #
  $self->SUPER::new($equation,$name,$ref);
}


1;
