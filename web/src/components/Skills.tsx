import { useId, useState } from 'react';
import type { SkillGroup } from '../generated/content';
import { countSkills, filterSkills } from '../lib/skills';
import { Section } from './Section';
import styles from './Skills.module.css';

type Props = { groups: SkillGroup[] };

export function Skills({ groups }: Props) {
  const [query, setQuery] = useState('');
  const inputId = useId();
  if (groups.length === 0) return null;

  const visible = filterSkills(groups, query);
  const count = countSkills(visible);
  return (
    <Section heading="Skills">
      <div className={styles.filter}>
        <label htmlFor={inputId}>Filter skills</label>
        <input
          id={inputId}
          type="search"
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
          }}
          autoComplete="off"
          spellCheck={false}
        />
      </div>
      <p role="status" className={styles.count}>
        {count === 0 ? 'No skills match.' : `${count} ${count === 1 ? 'skill' : 'skills'} shown`}
      </p>
      {visible.map((group) => (
        <div key={group.category} className={styles.group}>
          <h3 className={styles.category}>{group.category}</h3>
          <ul className={styles.items}>
            {group.items.map((item) => (
              <li key={item} className={styles.item}>
                {item}
              </li>
            ))}
          </ul>
        </div>
      ))}
    </Section>
  );
}
